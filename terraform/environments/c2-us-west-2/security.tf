# =============================================================================
# C2 (us-west-2) — Additional Security Group Rules
# =============================================================================
#
# This file adds least-privilege security group rules to the C2 environment.
# It references security group IDs from the EKS module and adds targeted
# ingress/egress rules using aws_security_group_rule resources (additive,
# won't conflict with module-managed rules).
#
# Requirements: 7.2, 7.4, 7.5, 7.6

# -----------------------------------------------------------------------------
# C2 Worker Nodes — Inbound from VPC CIDR on port 30550 (NLB → NodePort)
# -----------------------------------------------------------------------------
# NLBs operate at Layer 4 and do not have security groups. Traffic from the NLB
# arrives at worker nodes with the NLB's private IP (within the VPC CIDR) as
# the source. We scope ingress to the VPC CIDR rather than 0.0.0.0/0 to
# satisfy Requirement 7.5 (no unrestricted inbound on application ports).
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "worker_ingress_from_nlb" {
  description       = "Allow inbound TCP from VPC CIDR on NodePort 30550 (NLB forwards to productcatalogservice)"
  type              = "ingress"
  from_port         = var.node_port
  to_port           = var.node_port
  protocol          = "tcp"
  security_group_id = module.eks.node_security_group_id
  cidr_blocks       = [var.vpc_cidr]
}

# -----------------------------------------------------------------------------
# C2 Worker Nodes — Outbound to AWS service endpoints on port 443
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

# =============================================================================
# Network ACL — Private Subnet Hardening (Requirement 7.6)
# =============================================================================
#
# The private subnets in C2 use the default VPC NACL. Unlike C1, C2 has NO
# public subnets and NO Internet Gateway at all. This means:
#
#   1. No unsolicited inbound traffic from the public internet can reach
#      private subnets because there is no IGW in the VPC.
#   2. Outbound internet access (for ECR image pulls, etc.) goes through a
#      NAT Gateway whose return traffic is handled automatically.
#
# Adding restrictive NACL rules on private subnets risks breaking:
#   - NAT Gateway return traffic (ephemeral ports)
#   - VPC-internal communication (EKS control plane ↔ worker nodes)
#   - NLB → worker node traffic (NLB is in the same private subnets)
#   - PrivateLink endpoint service ENI traffic
#
# Therefore, the default NACL configuration is acceptable for private subnets.
# The absence of an IGW is the primary control preventing public inbound.
# Security groups provide the fine-grained, stateful filtering layer.
# =============================================================================
