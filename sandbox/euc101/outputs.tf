output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "autoscaling_group_id" {
  description = "ASG ID"
  value       = module.asg.autoscaling_group_id
}
