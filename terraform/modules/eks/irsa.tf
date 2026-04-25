# IRSA (IAM Roles for Service Accounts) — Example for Elastic Agent
#
# This creates an IAM role that can be assumed by the elastic-agent
# ServiceAccount in the elastic-system namespace. The role grants
# read-only access to CloudWatch and EC2 describe APIs, which the
# Elastic Agent needs for AWS infrastructure metrics collection.
#
# Usage: Annotate the ServiceAccount with:
#   eks.amazonaws.com/role-arn: <output.elastic_agent_role_arn>

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "elastic_agent" {
  name = "${var.cluster_name}-elastic-agent-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:elastic-system:elastic-agent"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Terraform = "true"
    Purpose   = "IRSA for Elastic Agent"
  }
}

resource "aws_iam_role_policy" "elastic_agent" {
  name = "${var.cluster_name}-elastic-agent-policy"
  role = aws_iam_role.elastic_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchReadOnly"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "logs:DescribeLogGroups",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2DescribeOnly"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "ELBReadOnly"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth"
        ]
        Resource = "*"
      }
    ]
  })
}
