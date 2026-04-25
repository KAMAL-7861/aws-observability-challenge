# Security group for the ALB: inbound HTTP from the internet, outbound to target group port
resource "aws_security_group" "alb" {
  name_prefix = "alb-sg-"
  description = "Security group for the internet-facing ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow traffic to target group port"
    from_port   = var.target_group_port
    to_port     = var.target_group_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "alb-sg"
    Terraform = "true"
  }
}

# Application Load Balancer — internet-facing, in public subnets
resource "aws_lb" "this" {
  name               = "frontend-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = {
    Name      = "frontend-alb"
    Terraform = "true"
  }
}

# Target group for frontend service (instance type for EKS worker nodes)
resource "aws_lb_target_group" "frontend" {
  name        = "frontend-tg"
  port        = var.target_group_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name      = "frontend-tg"
    Terraform = "true"
  }
}

# HTTP listener on port 80 forwarding to the frontend target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}
