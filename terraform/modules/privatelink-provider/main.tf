# --- Network Load Balancer ---

resource "aws_lb" "nlb" {
  name               = "privatelink-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  tags = {
    Terraform = "true"
    Purpose   = "PrivateLink provider for productcatalogservice"
  }
}

# --- Target Group (instance targets on NodePort) ---

resource "aws_lb_target_group" "productcatalog" {
  name        = "productcatalog-tg"
  port        = var.node_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = tostring(var.node_port)
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = {
    Terraform = "true"
  }
}

# --- NLB Listener ---

resource "aws_lb_listener" "grpc" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = var.service_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.productcatalog.arn
  }
}

# --- VPC Endpoint Service ---

resource "aws_vpc_endpoint_service" "this" {
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.nlb.arn]
  allowed_principals         = var.allowed_principals
  supported_regions          = var.supported_regions

  tags = {
    Terraform = "true"
    Purpose   = "PrivateLink endpoint service for productcatalogservice"
  }
}
