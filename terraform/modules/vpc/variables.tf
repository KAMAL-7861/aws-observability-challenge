variable "region" {
  description = "AWS region for the VPC"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster (used for subnet tagging)"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones to use for subnets (minimum 2)"
  type        = list(string)
}

variable "enable_public_subnets" {
  description = "Whether to create public subnets (required for ALB in C1, not needed for C2)"
  type        = bool
  default     = false
}
