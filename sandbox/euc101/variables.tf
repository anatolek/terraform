variable "region" {
  type        = string
  description = "The region where AWS operations will take place"
  default     = "eu-central-1"
}

variable "env_class" {
  type        = string
  description = "The environment class"
  default     = "sandbox"
}

variable "image_id" {
  type        = map(string)
  description = "AMI ID"
}

variable "instance_type" {
  type        = map(string)
  description = "ASG Instance type"
}

variable "root_volume_size" {
  type        = map(number)
  description = "Instance root volume size"
}

variable "root_volume_type" {
  type        = map(string)
  description = "Instance root volume type"
}
