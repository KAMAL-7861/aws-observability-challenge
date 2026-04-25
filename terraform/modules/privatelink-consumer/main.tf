# --- Security Group for VPC Endpoint ENIs ---

resource "aws_security_group" "endpoint" {
  name_prefix = "privatelink-endpoint-"
  description = "Security group for PrivateLink consumer VPC Endpoint ENIs"
  vpc_id      = var.vpc_id

  # Allow inbound on the service port from within the VPC
  ingress {
    description = "Allow gRPC traffic to VPC Endpoint ENIs"
    from_port   = var.service_port
    to_port     = var.service_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

  # Allow all outbound (endpoint ENIs need to reach the PrivateLink service)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Terraform = "true"
    Purpose   = "PrivateLink consumer endpoint ENIs"
  }
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

# --- VPC Endpoint (Interface type) for cross-region PrivateLink ---

resource "aws_vpc_endpoint" "this" {
  vpc_id              = var.vpc_id
  service_name        = var.endpoint_service_name
  vpc_endpoint_type   = "Interface"
  service_region      = var.service_region
  subnet_ids          = var.subnet_ids
  private_dns_enabled = false

  security_group_ids = concat(
    [aws_security_group.endpoint.id],
    var.security_group_ids
  )

  # Cross-region PrivateLink only supports full-access endpoint policy
  # Custom endpoint policies are not supported for cross-region connections

  tags = {
    Terraform = "true"
    Purpose   = "PrivateLink consumer endpoint for productcatalogservice"
  }
}
