variable "region" {
  description = "AWS region for the state backend resources"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state storage"
  type        = string
  default     = "obs-challenge-terraform-state"
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table for Terraform state locking"
  type        = string
  default     = "obs-challenge-terraform-locks"
}
