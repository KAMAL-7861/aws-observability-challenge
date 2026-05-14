region             = "us-east-1"
cluster_name       = "obs-challenge-c1"
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]
node_instance_type = "t3.medium"
node_count         = 2
target_group_port  = 8080
waf_rate_limit     = 1000
c2_service_region  = "us-west-2"

c2_endpoint_service_name = ""  # Set this after deploying C2: e.g. "com.amazonaws.vpce.us-west-2.vpce-svc-xxxxxxxxxxxxxxxxx"
