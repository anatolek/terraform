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
