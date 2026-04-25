# Architecture Diagram

## High-Level Architecture

```mermaid
graph TB
    subgraph "Internet"
        User[End User / Reviewer]
    end

    subgraph "us-east-1 — C1 Primary Cluster"
        subgraph "VPC 10.0.0.0/16"
            WAF[AWS WAF Web ACL<br/>SQLi + XSS + Rate Limit]
            ALB[Application Load Balancer<br/>HTTP :80 — PUBLIC]
            WAF --> ALB

            subgraph "Private Subnets"
                EKS1[EKS Cluster: obs-challenge-c1]
                subgraph "C1 Pods — online-boutique namespace"
                    FE[frontend :8080]
                    Cart[cartservice :7070]
                    Checkout[checkoutservice :5050]
                    Currency[currencyservice :7000]
                    Email[emailservice :8080]
                    Payment[paymentservice :50051]
                    Recommend[recommendationservice :8080]
                    Shipping[shippingservice :50051]
                    Ad[adservice :9555]
                    Redis[redis-cart :6379]
                    EA1[Elastic Agent DaemonSet]
                end
                ExtSvc[ExternalName Service<br/>productcatalogservice-external :3550]
                VPCE[VPC Endpoint — Interface Type<br/>PrivateLink Consumer]
            end
        end
    end

    subgraph "us-west-2 — C2 Secondary Cluster"
        subgraph "VPC 10.1.0.0/16"
            subgraph "Private Subnets"
                EKS2[EKS Cluster: obs-challenge-c2]
                subgraph "C2 Pods — online-boutique namespace"
                    PCS[productcatalogservice :3550]
                    EA2[Elastic Agent DaemonSet]
                end
            end
            NLB[Network Load Balancer<br/>TCP :3550 — INTERNAL]
            VPCES[VPC Endpoint Service<br/>PrivateLink Provider]
        end
    end

    subgraph "Elastic Cloud — Free Trial"
        Fleet[Fleet Server]
        ES[Elasticsearch]
        Kibana[Kibana Dashboards + Alerts]
    end

    User -->|HTTP :80| WAF
    ALB -->|HTTP :8080| FE
    FE -->|gRPC| ExtSvc
    Checkout -->|gRPC| ExtSvc
    Recommend -->|gRPC| ExtSvc
    ExtSvc -->|DNS resolves to| VPCE
    VPCE -.->|PrivateLink Cross-Region| VPCES
    VPCES --> NLB
    NLB -->|TCP :3550 → NodePort :30550| PCS

    EA1 -->|logs + metrics| Fleet
    EA2 -->|logs + metrics| Fleet
    Fleet --> ES
    ES --> Kibana
```

## Network Flow: Cross-Cluster gRPC Request

```
User → ALB (:80) → frontend (:8080) → ExternalName Service
  → VPC Endpoint DNS → PrivateLink (cross-region, private)
  → NLB (:3550) → NodePort (:30550) → productcatalogservice (:3550)
  → Response returns same path
```

## Service Mapping

| Service | Cluster | Region | Port | Notes |
|---------|---------|--------|------|-------|
| frontend | C1 | us-east-1 | 8080 | Public via ALB+WAF |
| cartservice | C1 | us-east-1 | 7070 | Internal only |
| checkoutservice | C1 | us-east-1 | 5050 | Calls productcatalog via PrivateLink |
| currencyservice | C1 | us-east-1 | 7000 | Internal only |
| emailservice | C1 | us-east-1 | 8080 | Internal only |
| paymentservice | C1 | us-east-1 | 50051 | Internal only |
| recommendationservice | C1 | us-east-1 | 8080 | Calls productcatalog via PrivateLink |
| shippingservice | C1 | us-east-1 | 50051 | Internal only |
| adservice | C1 | us-east-1 | 9555 | Internal only |
| redis-cart | C1 | us-east-1 | 6379 | Internal only |
| productcatalogservice | C2 | us-west-2 | 3550 | Isolated in C2, exposed via PrivateLink |

## Security Boundaries

- **Public**: Only ALB has a public endpoint (port 80)
- **Private**: All EKS nodes, NLB, VPC Endpoint — no public IPs
- **WAF**: SQLi, XSS, rate limiting (1000 req/5min) in BLOCK mode
- **PrivateLink**: Unidirectional, service-oriented — C1 can reach C2, not vice versa
- **Security Groups**: Least-privilege, SG-to-SG references where possible
