region             = "us-west-2"
cluster_name       = "obs-challenge-c2"
vpc_cidr           = "10.1.0.0/16"
availability_zones = ["us-west-2a", "us-west-2b"]
node_instance_type = "t3.medium"
node_count         = 2
service_port       = 3550
node_port          = 30550

# Allow the same AWS account to connect via PrivateLink
allowed_principals = ["arn:aws:iam::YOUR_AWS_ACCOUNT_ID:root"]
