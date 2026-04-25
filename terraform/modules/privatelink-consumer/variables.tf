variable "vpc_id" {
  description = "ID of the VPC where the VPC Endpoint will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for the VPC Endpoint ENIs"
  type        = list(string)
}

variable "endpoint_service_name" {
  description = "Service name of the VPC Endpoint Service in the provider region (e.g., com.amazonaws.vpce.us-west-2.vpce-svc-xxx)"
  type        = string
}

variable "service_region" {
  description = "AWS region where the endpoint service is hosted (for cross-region PrivateLink)"
  type        = string
  default     = "us-west-2"
}

variable "security_group_ids" {
  description = "List of security group IDs to associate with the VPC Endpoint ENIs"
  type        = list(string)
  default     = []
}

variable "service_port" {
  description = "TCP port for the service (used in security group ingress rule)"
  type        = number
  default     = 3550
}
