variable "alb_arn" {
  description = "ARN of the ALB to associate the WAF Web ACL with"
  type        = string
}

variable "rate_limit_threshold" {
  description = "Maximum number of requests allowed from a single IP in a 5-minute window"
  type        = number
  default     = 1000
}
