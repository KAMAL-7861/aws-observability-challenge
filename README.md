# AWS Application and Infrastructure Observability Challenge

A production-grade multi-region AWS architecture deploying [Google Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) across two EKS clusters connected via AWS PrivateLink, protected by ALB and WAF, and monitored with Elastic observability.

## Architecture Overview

```
Internet → WAF → ALB (us-east-1)
                    ↓
              Frontend (C1)
                    ↓ gRPC
         ExternalName Service (C1)
                    ↓
           VPC Endpoint (C1)
                    ↓ PrivateLink (cross-region)
           VPC Endpoint Service (C2)
                    ↓
              NLB (C2)
                    ↓
     productcatalogservice (C2, us-west-2)
```

- **C1 (us-east-1)** — Primary cluster hosting the frontend and all Online Boutique services except productcatalogservice
- **C2 (us-west-2)** — Secondary cluster hosting productcatalogservice exclusively
- **PrivateLink** — Private cross-region connectivity between C1 and C2 (no public internet)
- **ALB + WAF** — Public-facing load balancer with managed rule groups and rate limiting
- **Elastic Agent** — DaemonSet on both clusters shipping logs and metrics to Elastic Cloud

## Repository Structure

```
├── terraform/
│   ├── state-bootstrap/          # S3 backend + DynamoDB lock table
│   ├── modules/
│   │   ├── vpc/                  # Reusable VPC module
│   │   ├── eks/                  # Reusable EKS module
│   │   ├── alb/                  # ALB + target group
│   │   ├── waf/                  # WAF Web ACL + rules
│   │   ├── privatelink-provider/ # NLB + VPC Endpoint Service (C2)
│   │   └── privatelink-consumer/ # VPC Endpoint (C1)
│   ├── environments/
│   │   ├── c1-us-east-1/         # C1 environment config
│   │   └── c2-us-west-2/         # C2 environment config
│   └── scripts/
│       ├── deploy.sh             # Full infrastructure deploy
│       └── destroy.sh            # Full infrastructure teardown
├── k8s/
│   ├── c1/                       # C1 Kubernetes manifests
│   │   ├── online-boutique/      # All services except productcatalogservice
│   │   ├── external-service.yaml # ExternalName service → VPC Endpoint
│   │   └── elastic-agent/        # Elastic Agent DaemonSet
│   ├── c2/                       # C2 Kubernetes manifests
│   │   ├── productcatalogservice.yaml
│   │   ├── nodeport-service.yaml # NodePort for NLB target group
│   │   └── elastic-agent/        # Elastic Agent DaemonSet
│   └── scripts/
│       ├── deploy-c1.sh
│       ├── deploy-c2.sh
│       └── deploy-elastic-agent.sh
├── verification/                 # Python security verification tool
│   ├── verify.py                 # CLI entry point
│   ├── checks/                   # Individual check modules
│   └── tests/                    # Property-based tests (Hypothesis)
├── scripts/
│   └── fault-sim.sh              # Fault simulation script
└── docs/
    ├── design-writeup.md         # Architecture decisions and rationale
    ├── fault-simulation-guide.md # Manual fault simulation walkthrough
    ├── elastic-dashboard-setup.md
    └── elastic-alert-setup.md
```

## Prerequisites

- AWS CLI configured with sufficient permissions (EKS, EC2, VPC, IAM, WAF, S3, DynamoDB)
- Terraform >= 1.0
- kubectl
- Helm (for Elastic Agent deployment)
- Python 3.9+ (for verification tool)

## Deployment

### 1. Bootstrap Terraform State

```bash
cd terraform/state-bootstrap
terraform init
terraform apply
```

This creates the S3 bucket and DynamoDB table for remote state.

### 2. Configure Variables

Update `terraform/environments/c2-us-west-2/terraform.tfvars`:
```hcl
allowed_principals = ["arn:aws:iam::YOUR_AWS_ACCOUNT_ID:root"]
```

### 3. Deploy All Infrastructure

```bash
bash terraform/scripts/deploy.sh
```

This deploys C2 first (NLB + PrivateLink provider), then C1 (EKS + ALB + WAF + PrivateLink consumer). Takes approximately 45-50 minutes.

After C2 deploys, copy the `endpoint_service_name` output into `terraform/environments/c1-us-east-1/terraform.tfvars`:
```hcl
c2_endpoint_service_name = "com.amazonaws.vpce.us-west-2.vpce-svc-xxxxxxxxxxxxxxxxx"
```

### 4. Configure kubectl

```bash
aws eks update-kubeconfig --name obs-challenge-c2 --region us-west-2 --alias c2
aws eks update-kubeconfig --name obs-challenge-c1 --region us-east-1 --alias c1
```

### 5. Deploy Applications

```bash
bash k8s/scripts/deploy-c2.sh   # Deploy productcatalogservice to C2
bash k8s/scripts/deploy-c1.sh   # Deploy all other services to C1
```

### 6. Verify Deployment

```bash
kubectl get pods -n online-boutique --context=c1
kubectl get pods -n online-boutique --context=c2

# Get ALB URL
kubectl get svc frontend-external -n online-boutique --context=c1
```

Open the ALB URL in your browser — the storefront should display products served from C2 via PrivateLink.

## Verification Tool

The Python verification tool validates the security posture programmatically:

```bash
cd verification
pip install -r requirements.txt

python verify.py \
  --c1-region us-east-1 \
  --c1-cluster obs-challenge-c1 \
  --c2-region us-west-2 \
  --c2-cluster obs-challenge-c2 \
  --output json
```

Checks performed:
- No EKS worker nodes have public IP addresses
- VPC Endpoint and Endpoint Service are in `available` state
- WAF Web ACL is associated with the ALB
- No security groups allow unrestricted inbound access (0.0.0.0/0) on application ports

Run property-based tests:
```bash
pytest verification/tests/ -v
```

## Fault Simulation

To demonstrate that the frontend depends on C2's productcatalogservice:

```bash
# Stop productcatalogservice permanently (Kubernetes won't restart it)
kubectl scale deployment productcatalogservice -n online-boutique --context=c2 --replicas=0

# Watch frontend logs for gRPC errors
kubectl logs -l app=frontend -n online-boutique --context=c1 --tail=100

# Restore
kubectl scale deployment productcatalogservice -n online-boutique --context=c2 --replicas=1
```

See [docs/fault-simulation-guide.md](docs/fault-simulation-guide.md) for the full walkthrough including AWS Console verification steps.

## Teardown

```bash
bash terraform/scripts/destroy.sh
```

This destroys all AWS resources in reverse order (C1 first, then C2, then state bootstrap).

## Key Design Decisions

**PrivateLink over VPC Peering** — PrivateLink provides a unidirectional, service-oriented connection. Unlike VPC peering, it doesn't expose the entire VPC network — only the specific service endpoint. AWS PrivateLink supports native cross-region connectivity (launched Nov 2024) via the `service_region` parameter.

**productcatalogservice as the split service** — The frontend calls productcatalogservice directly via gRPC using the `PRODUCT_CATALOG_SERVICE_ADDR` environment variable. This is the cleanest split point — it's a direct frontend dependency, making the cross-cluster call visible in the user experience.

**ExternalName Service for DNS** — A Kubernetes ExternalName service in C1 maps to the VPC Endpoint DNS name, letting the frontend resolve the remote service using standard Kubernetes DNS without any application-level awareness of PrivateLink.

## Security Controls

| Layer | Control |
|-------|---------|
| Network | Worker nodes in private subnets, no public IPs |
| Network | Security groups with least-privilege rules |
| Network | PrivateLink — no traffic traverses public internet |
| Application | WAF with AWSManagedRulesCommonRuleSet + rate limiting |
| State | S3 backend with versioning, AES-256 encryption, public access blocked |
| State | DynamoDB state locking |
| Endpoint | VPC Endpoint policy restricting authorized principals |
