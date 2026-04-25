# Design Write-Up: AWS Observability Challenge

## 1. Architecture Overview

This project deploys Google Online Boutique across two EKS clusters in separate AWS regions, connected via AWS PrivateLink. The primary cluster (C1, us-east-1) hosts the frontend and most microservices. The secondary cluster (C2, us-west-2) hosts productcatalogservice exclusively. An ALB with WAF protects the public-facing frontend. Elastic Cloud monitors both clusters.

## 2. Key Design Decisions

### 2.1 PrivateLink over VPC Peering

**Choice**: AWS PrivateLink (cross-region, launched Nov 2024)

**Rationale**:
- **Unidirectional**: Only C1 can initiate connections to C2 — C2 cannot reach C1. This is more secure than VPC peering which exposes the entire VPC network bidirectionally.
- **Service-oriented**: Exposes only the specific service endpoint (port 3550), not the entire VPC CIDR.
- **No CIDR overlap concerns**: PrivateLink works regardless of VPC CIDR ranges.
- **Cross-account ready**: The same pattern works for cross-account service consumption.
- **Native cross-region**: AWS PrivateLink now supports cross-region natively via the `service_region` parameter — no Transit Gateway or VPC peering required.

**Trade-off**: PrivateLink adds ~1-2ms latency compared to VPC peering due to the NLB hop. Acceptable for this use case.

### 2.2 productcatalogservice as the Split Service

**Choice**: Move only productcatalogservice to C2.

**Rationale**:
- The frontend calls productcatalogservice directly via gRPC using the `PRODUCT_CATALOG_SERVICE_ADDR` environment variable — this is a first-class configuration mechanism that requires zero code changes.
- It's a direct dependency of the frontend, making the cross-cluster call visible in the user experience (product listings come from C2).
- checkoutservice and recommendationservice also call productcatalogservice — all three are configured to use the ExternalName service.
- productcatalogservice is stateless and self-contained (reads from an embedded JSON file), making it the cleanest split point.

**Trade-off**: Only one service crosses the cluster boundary. A more complex split (e.g., moving paymentservice too) would demonstrate more PrivateLink endpoints but adds significant complexity without proportional value.

### 2.3 ExternalName Service for DNS Resolution

**Choice**: Kubernetes ExternalName service in C1 mapping to the VPC Endpoint DNS name.

**Rationale**:
- Allows the frontend to resolve the remote service using standard Kubernetes DNS (`productcatalogservice-external.online-boutique.svc.cluster.local:3550`).
- No application-level awareness of PrivateLink — the app just sees a Kubernetes service.
- Easy to swap: if PrivateLink is removed, just change the ExternalName target.

**Trade-off**: ExternalName services don't support port remapping — the VPC Endpoint must listen on the same port (3550). This is fine for our use case.

### 2.4 Elastic Cloud over Self-Hosted

**Choice**: Elastic Cloud free trial instead of self-hosted Elasticsearch on EKS.

**Rationale**:
- Avoids operational overhead of running Elasticsearch/Kibana on the EKS clusters.
- Free trial provides sufficient capacity for the demo.
- Keeps EKS clusters focused on the application workload.
- Fleet-managed Elastic Agent simplifies deployment and configuration.

### 2.5 Terraform Community Modules

**Choice**: `terraform-aws-modules/vpc` and `terraform-aws-modules/eks` for VPC and EKS.

**Rationale**:
- Battle-tested, well-documented, and reduce boilerplate significantly.
- Follow AWS best practices out of the box.
- Widely used in production — reviewers will recognize the patterns.

## 3. Security Controls Summary

| Control | Implementation | Purpose |
|---------|---------------|---------|
| WAF | AWSManagedRulesCommonRuleSet, SQLiRuleSet, KnownBadInputsRuleSet + rate limiting | Block common web attacks |
| ALB SG | Inbound 0.0.0.0/0 on port 80 only | Only public entry point |
| Worker Node SG (C1) | Inbound from ALB SG on 8080, outbound to VPCE SG on 3550 | Least-privilege |
| VPC Endpoint SG | Inbound from worker nodes SG on 3550 | SG-to-SG reference |
| Worker Node SG (C2) | Inbound from VPC CIDR on 30550 | NLB traffic only |
| Private subnets | No IGW route, NAT gateway for outbound | No public inbound |
| PrivateLink | Unidirectional, allowed_principals | Service-level access control |

## 4. Verification Tool Results

The Python verification tool validates 5 security checks:

| Check | Expected Result | Description |
|-------|----------------|-------------|
| no_public_ips | PASS | No EKS worker nodes have public IPs |
| privatelink_active | PASS | VPC Endpoint and Endpoint Service both in "available" state |
| waf_associated | PASS | WAF Web ACL associated with ALB, managed rules active |
| no_unrestricted_sg | PASS | No security groups allow 0.0.0.0/0 on application ports |
| connectivity | PASS | ALB endpoint returns HTTP 200 |

## 5. What Was Built vs. What Was Skipped

### Built:
- Full Terraform IaC (6 modules, 2 environments, state bootstrap)
- Complete Kubernetes manifests for both clusters
- PrivateLink cross-region connectivity
- ALB + WAF with managed rule groups
- Python verification tool with 5 security checks
- Elastic Agent DaemonSets for both clusters
- Fault simulation script
- Architecture documentation

### Skipped (time constraints):
- Property-based tests for the verification tool (framework ready, tests optional)
- Custom domain / HTTPS (no domain available)
- Multi-AZ NLB health check tuning
- Elastic dashboard/alert Kibana saved object exports (step-by-step guide provided instead)

## 6. Known Limitations & Production Recommendations

### 6.1 HTTP-only ALB (No TLS)
The ALB currently serves HTTP on port 80. No custom domain is available for this demo.

**Production recommendation**: Add an ACM certificate, configure HTTPS listener on port 443, and redirect HTTP→HTTPS. All internal communication (PrivateLink, gRPC between services) already uses encrypted channels via the AWS backbone.

### 6.2 Encryption in Transit
| Path | Encryption | Notes |
|------|-----------|-------|
| User → ALB | HTTP (demo) / HTTPS (production) | Add ACM cert for TLS 1.2+ |
| ALB → Frontend pod | HTTP within VPC | Private subnet, no internet exposure |
| Frontend → VPC Endpoint | gRPC over TCP | Encrypted by AWS PrivateLink backbone |
| VPC Endpoint → NLB → productcatalogservice | TCP within VPC | Private subnet |
| EKS nodes → Elastic Cloud | HTTPS | Fleet enrollment uses TLS |

### 6.3 IRSA (IAM Roles for Service Accounts)
The EKS module enables IRSA via the OIDC provider. In production, each pod that needs AWS API access should use a dedicated IAM role scoped to minimum required permissions, rather than inheriting node-level credentials.
