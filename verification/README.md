# AWS Verification Tool

Programmatically validates the security posture and connectivity of the
multi-region EKS architecture.

## Prerequisites

- Python 3.10+
- AWS credentials configured (`aws configure` or environment variables)
- IAM permissions: `ec2:DescribeInstances`, `ec2:DescribeVpcEndpoints`,
  `ec2:DescribeVpcEndpointServiceConfigurations`, `ec2:DescribeSecurityGroups`,
  `wafv2:ListWebACLs`, `wafv2:GetWebACL`, `wafv2:ListResourcesForWebACL`
- `pip install -r verification/requirements.txt`

## Installation

```bash
pip install -r verification/requirements.txt
```

## Usage

### Run all checks (text output)

```bash
python -m verification.verify \
    --c1-region us-east-1 --c1-cluster obs-challenge-c1 \
    --c2-region us-west-2 --c2-cluster obs-challenge-c2 \
    --alb-url http://my-alb-1234.us-east-1.elb.amazonaws.com \
    --output text
```

### Run all checks (JSON output)

```bash
python -m verification.verify \
    --c1-region us-east-1 --c1-cluster obs-challenge-c1 \
    --c2-region us-west-2 --c2-cluster obs-challenge-c2 \
    --alb-url http://my-alb-1234.us-east-1.elb.amazonaws.com \
    --vpc-endpoint-id vpce-0abc123 \
    --endpoint-service-id vpce-svc-0def456 \
    --alb-arn arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-alb/abc123 \
    --output json
```

### Show help

```bash
python -m verification.verify --help
```

## Checks

| Check | Description |
|-------|-------------|
| `no_public_ips_on_worker_nodes` | Verifies no EKS worker node has a public IP |
| `privatelink_active` | Verifies VPC Endpoint and Endpoint Service are "available" |
| `waf_associated` | Verifies WAF Web ACL is associated with the ALB with managed rules |
| `no_unrestricted_sg_ingress` | Verifies no SG allows 0.0.0.0/0 or ::/0 on app ports (3550, 8080, 30550) |
| `connectivity_check` | Sends HTTP request to ALB and verifies HTTP 200 |

## Example JSON Output

### All checks pass

```json
{
  "timestamp": "2024-01-15T10:30:00+00:00",
  "summary": {
    "total_checks": 5,
    "passed": 5,
    "failed": 0
  },
  "checks": [
    {
      "check_name": "no_public_ips_on_worker_nodes",
      "passed": true,
      "resource_id": "i-0abc123def456",
      "details": "Instance i-0abc123def456 has no public IP",
      "remediation": null
    },
    {
      "check_name": "privatelink_active",
      "passed": true,
      "resource_id": "vpce-0abc123",
      "details": "VPC Endpoint vpce-0abc123 is in 'available' state",
      "remediation": null
    },
    {
      "check_name": "waf_associated",
      "passed": true,
      "resource_id": "arn:aws:wafv2:::webacl/my-acl/abc123",
      "details": "WAF Web ACL is associated with ALB and has managed rule groups",
      "remediation": null
    },
    {
      "check_name": "no_unrestricted_sg_ingress",
      "passed": true,
      "resource_id": "sg-0abc123",
      "details": "No unrestricted inbound rules on application ports",
      "remediation": null
    },
    {
      "check_name": "connectivity_check",
      "passed": true,
      "resource_id": "my-alb.elb.amazonaws.com",
      "details": "ALB endpoint returned HTTP 200",
      "remediation": null
    }
  ]
}
```

### Check failure example

```json
{
  "timestamp": "2024-01-15T10:30:00+00:00",
  "summary": {
    "total_checks": 2,
    "passed": 1,
    "failed": 1
  },
  "checks": [
    {
      "check_name": "no_public_ips_on_worker_nodes",
      "passed": true,
      "resource_id": "i-0abc123def456",
      "details": "Instance i-0abc123def456 has no public IP",
      "remediation": null
    },
    {
      "check_name": "no_unrestricted_sg_ingress",
      "passed": false,
      "resource_id": "sg-0bad456",
      "details": "Security group sg-0bad456 allows 0.0.0.0/0 on ports 3550-3550",
      "remediation": "Remove the 0.0.0.0/0 inbound rule on ports 3550-3550 from security group sg-0bad456"
    }
  ]
}
```

## Manual Verification Commands (AWS CLI)

### Check EC2 public IPs

```bash
aws ec2 describe-instances \
    --filters "Name=tag:kubernetes.io/cluster/obs-challenge-c1,Values=owned" \
    --query "Reservations[].Instances[].[InstanceId,PublicIpAddress]" \
    --region us-east-1
```

### Check VPC Endpoint state

```bash
aws ec2 describe-vpc-endpoints \
    --vpc-endpoint-ids vpce-0abc123 \
    --query "VpcEndpoints[].State" \
    --region us-east-1
```

### Check VPC Endpoint Service state

```bash
aws ec2 describe-vpc-endpoint-service-configurations \
    --service-ids vpce-svc-0def456 \
    --query "ServiceConfigurations[].ServiceState" \
    --region us-west-2
```

### Check WAF association

```bash
aws wafv2 list-web-acls --scope REGIONAL --region us-east-1
aws wafv2 list-resources-for-web-acl \
    --web-acl-arn <web_acl_arn> \
    --resource-type APPLICATION_LOAD_BALANCER \
    --region us-east-1
```

### Check security group rules

```bash
aws ec2 describe-security-groups \
    --group-ids sg-0abc123 \
    --query "SecurityGroups[].IpPermissions" \
    --region us-east-1
```

### Test ALB connectivity

```bash
curl -s -o /dev/null -w "%{http_code}" http://my-alb.elb.amazonaws.com/
```

## Running Tests

```bash
# Run all tests
pytest verification/tests/ -v

# Run property-based tests only
pytest verification/tests/ -v -k "property"
```

## How to Interpret Results

Each check produces a **PASS** or **FAIL** result:

- **PASS** — the resource meets the security or connectivity requirement.
- **FAIL** — a violation was detected. The output includes:
  - `resource_id` — the specific AWS resource that failed.
  - `remediation` — a suggested action to fix the issue.

The **exit code** tells you the overall outcome:
- `0` — all checks passed.
- `1` — one or more checks failed.
- `2` — execution error (timeout, invalid arguments).

In JSON mode the `summary` object gives you `total_checks`, `passed`, and
`failed` counts at a glance. In text mode a one-line summary is printed at
the bottom.
