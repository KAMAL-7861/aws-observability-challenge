variable "vpc_id" {
  description = "ID of the VPC where the NLB and Endpoint Service will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for the NLB"
  type        = list(string)
}

variable "service_port" {
  description = "TCP port the NLB listens on (productcatalogservice gRPC port)"
  type        = number
  default     = 3550
}

variable "node_port" {
  description = "NodePort on EKS worker nodes that forwards to productcatalogservice"
  type        = number
  default     = 30550
}

variable "allowed_principals" {
  description = "List of AWS principal ARNs allowed to create VPC Endpoint connections to this service"
  type        = list(string)
}

variable "node_security_group_id" {
  description = "Security group ID of the EKS worker nodes (used for NLB target group)"
  type        = string
}

variable "supported_regions" {
  description = "List of AWS regions allowed to consume this endpoint service (for cross-region PrivateLink)"
  type        = list(string)
  default     = []
}
