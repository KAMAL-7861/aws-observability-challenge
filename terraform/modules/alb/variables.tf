variable "vpc_id" {
  description = "ID of the VPC where the ALB and target group are created"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "target_group_port" {
  description = "Port on which the target group receives traffic (frontend service port)"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "HTTP path for ALB health checks against the frontend service"
  type        = string
  default     = "/"
}
