############## AWS Provider ############
provider "aws" {
  region = var.region
}

########## Configure TF backend #########
terraform {
  #  backend "s3" {
  #    bucket         = "euc101-sandbox-terraform-state"
  #    key            = "terraform.tfstate"
  #    region         = "eu-central-1"
  #    dynamodb_table = "tf_lock"
  #  }
  backend "local" {
    path = "terraform.tfstate"
  }
}

############ Common composed values shared across the different modules ############
locals {
  env_name = terraform.workspace
  common_tags = {
    EnvClass    = var.env_class
    Environment = local.env_name
    Owner       = "DevOps"
    Terraform   = "true"
  }
  user_data = <<-EOT
  #!/bin/bash
  yum update
  EOT
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = "${local.env_name}-${var.env_class}-vpc"
  cidr = "10.0.0.0/16"

  azs             = formatlist("${var.region}%s", ["a", "b", "c"])
  private_subnets = []
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  tags = local.common_tags

  vpc_tags = {
    Name = "${local.env_name}-${var.env_class}-vpc"
  }
}

module "web_server_sg" {
  source  = "terraform-aws-modules/security-group/aws//modules/http-80"
  version = "~> 4.0"

  name        = "web-server"
  description = "Security group for web-server with HTTP ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = [module.vpc.vpc_cidr_block]

  tags = local.common_tags
}

module "asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 6.0"

  # Autoscaling group
  name = "${local.env_name}-${var.env_class}-asg"

  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 2
  wait_for_capacity_timeout = 0
  health_check_type         = "EC2"
  vpc_zone_identifier       = module.vpc.public_subnets
  security_groups           = [module.web_server_sg.security_group_id]

  # Launch template
  launch_template_name        = "${local.env_name}-${var.env_class}-lt"
  launch_template_description = "${local.env_name}.${var.env_class} launch template"
  update_default_version      = true

  image_id      = var.image_id[local.env_name]
  instance_type = var.instance_type[local.env_name]
  user_data     = base64encode(local.user_data)
  ebs_optimized = false

  create_iam_instance_profile = true
  iam_role_name               = "${local.env_name}-${var.env_class}-asg-role"
  iam_role_path               = "/ec2/"
  iam_role_description        = "${local.env_name}.${var.env_class} IAM role"
  iam_role_tags               = local.common_tags
  iam_role_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  block_device_mappings = [
    {
      # Root volume
      device_name = "/dev/xvda"
      no_device   = 0
      ebs = {
        delete_on_termination = true
        encrypted             = true
        volume_size           = var.root_volume_size[local.env_name]
        volume_type           = var.root_volume_type[local.env_name]
      }
    }
  ]

  instance_market_options = {
    market_type = "spot"
    spot_options = {
      max_price = "0.008"
    }
  }

  tags = local.common_tags

  # Autoscaling Schedule
  schedules = {
    start_work = {
      min_size         = 1
      max_size         = 3
      desired_capacity = 1
      recurrence       = "0 8 * * 1-5" # Mon-Fri in the morning
      time_zone        = "Europe/Kyiv"
    }

    end_work = {
      min_size         = 0
      max_size         = 0
      desired_capacity = 0
      recurrence       = "0 19 * * 1-5" # Mon-Fri in the evening
      time_zone        = "Europe/Kyiv"
    }
  }

  # Autoscaling Policy
  # -----------------------------------------------
  #     -infinity   40%          80%   infinity
  # -----------------------------------------------
  #         -2       | Unchanged  |      +2
  # -----------------------------------------------
  scaling_policies = {
    step-downscaling-policy = {
      policy_type             = "StepScaling"
      adjustment_type         = "ChangeInCapacity"
      metric_aggregation_type = "Average"
      step_adjustment = {
        scaling_adjustment          = -2
        metric_interval_upper_bound = 0
      }
    }
    simple-upscaling-policy = {
      policy_type             = "SimpleScaling"
      adjustment_type         = "ChangeInCapacity"
      cooldown                = 60
      metric_aggregation_type = "Average"
      scaling_adjustment      = 2
    }
  }
}

module "autoscale_down_alarm" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "~> 4.0"

  alarm_name          = "${local.env_name}-${var.env_class}-asg-scale-down"
  alarm_description   = "This metric monitors EC2 CPU utilization lowering 40%"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 40
  period              = 60
  dimensions = {
    AutoScalingGroupName = module.asg.autoscaling_group_name
  }

  namespace   = "AWS/EC2"
  metric_name = "CPUUtilization"
  statistic   = "Maximum"

  alarm_actions = [module.asg.autoscaling_policy_arns["step-downscaling-policy"]]

  tags = local.common_tags
}

module "autoscale_up_alarm" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "~> 4.0"

  alarm_name          = "${local.env_name}-${var.env_class}-asg-scale-up"
  alarm_description   = "This metric monitors EC2 CPU utilization exceeding 80%"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 80
  period              = 60
  dimensions = {
    AutoScalingGroupName = module.asg.autoscaling_group_name
  }

  namespace   = "AWS/EC2"
  metric_name = "CPUUtilization"
  statistic   = "Maximum"

  alarm_actions = [module.asg.autoscaling_policy_arns["simple-upscaling-policy"]]

  tags = local.common_tags
}
