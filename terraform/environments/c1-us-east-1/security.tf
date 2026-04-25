# =============================================================================
# C1 (us-east-1) — Additional Security Group Rules
# =============================================================================
#
# This file adds least-privilege security group rules to the C1 environment.
# It references security group IDs from the EKS, ALB, and PrivateLink consumer
# modules and adds targeted ingress/egress rules using aws_security_group_rule
# resources (additive, won't conflict with module-managed rules).
#
# Requirements: 7.1, 7.3, 7.5

# -----------------------------------------------------------------------------
# C1 Worker Nodes — Inbound from ALB on port 8080 (frontend traffic)
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "worker_ingress_from_alb" {
  description              = "Allow inbound HTTP from ALB to frontend on port 8080"
  type                     = "ingress"
  from_port                = var.target_group_port
  to_port                  = var.target_group_port
  protocol                 = "tcp"
  security_group_id        = module.eks.node_security_group_id
  source_security_group_id = module.alb.alb_security_group_id
}

# -----------------------------------------------------------------------------
# C1 Worker Nodes — Outbound to VPC Endpoint SG on port 3550 (gRPC to C2)
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "worker_egress_to_vpce" {
  description              = "Allow outbound gRPC to VPC Endpoint ENIs on port 3550"
  type                     = "egress"
  from_port                = 3550
  to_port                  = 3550
  protocol                 = "tcp"
  security_group_id        = module.eks.node_security_group_id
  source_security_group_id = module.privatelink_consumer.endpoint_security_group_id
}

# -----------------------------------------------------------------------------
# C1 Worker Nodes — Outbound to AWS service endpoints on port 443
# (ECR, S3, STS, EKS API, CloudWatch, etc.)
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "worker_egress_https" {
  description       = "Allow outbound HTTPS to AWS service endpoints"
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = module.eks.node_security_group_id
  cidr_blocks       = ["0.0.0.0/0"]
}

# -----------------------------------------------------------------------------
# VPC Endpoint ENIs — Inbound from C1 worker nodes SG on port 3550
# The privatelink-consumer module already allows inbound from the VPC CIDR.
# This SG-to-SG rule provides a tighter, identity-based control.
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "vpce_ingress_from_workers" {
  description              = "Allow inbound gRPC from C1 worker nodes on port 3550"
  type                     = "ingress"
  from_port                = 3550
  to_port                  = 3550
  protocol                 = "tcp"
  security_group_id        = module.privatelink_consumer.endpoint_security_group_id
  source_security_group_id = module.eks.node_security_group_id
}

# -----------------------------------------------------------------------------
# ALB Security Group
# Already configured in the ALB module with:
#   - Inbound: 0.0.0.0/0 on port 80 (public HTTP access)
#   - Outbound: target_group_port to targets
# No additional rules needed here. The ALB SG is the only SG permitted to
# have 0.0.0.0/0 inbound, and only on port 80 (not an application port).
# -----------------------------------------------------------------------------

# =============================================================================
# Network ACL — Private Subnet Hardening (Requirement 7.6)
# =============================================================================
#
# The private subnets in C1 use the default VPC NACL. Private subnets have NO
# route to an Internet Gateway — outbound internet access goes through the NAT
# Gateway in the public subnet. This means:
#
#   1. No unsolicited inbound traffic from the public internet can reach
#      private subnets because there is no IGW route in the private route table.
#   2. Return traffic for NAT'd connections is handled by the NAT Gateway.
#
# Adding restrictive NACL rules on private subnets risks breaking:
#   - NAT Gateway return traffic (ephemeral ports)
#   - VPC-internal communication (EKS control plane ↔ worker nodes)
#   - ALB → worker node traffic (ALB is in public subnets, targets in private)
#   - VPC Endpoint ENI traffic
#
# Therefore, the default NACL configuration is acceptable for private subnets.
# The absence of an IGW route is the primary control preventing public inbound.
# Security groups provide the fine-grained, stateful filtering layer.
# =============================================================================
