variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the EKS cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for the EKS cluster and worker nodes"
  type        = list(string)
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group"
  type        = string
  default     = "t3.medium"
}

variable "node_count" {
  description = "Desired number of worker nodes in the managed node group"
  type        = number
  default     = 2
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.30"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks allowed to access the public EKS API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
