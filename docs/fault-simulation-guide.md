# Fault Simulation Guide: Cross-Cluster Dependency Verification

## Overview

This document demonstrates that the frontend application in C1 (us-east-1) is fully dependent on the productcatalogservice backend running in C2 (us-west-2). When C2's backend is stopped, the frontend degrades — proving the cross-cluster PrivateLink connectivity is real and not cached or faked.

## Architecture Recap

```
User → ALB (us-east-1) → Frontend (C1) → ExternalName Service → VPC Endpoint → PrivateLink → NLB (C2) → productcatalogservice (C2)
```

The frontend in C1 calls productcatalogservice in C2 via gRPC over PrivateLink. If productcatalogservice is unavailable, the frontend cannot display products.

## What Breaks When C2 Backend Is Stopped

| Component | Impact |
|-----------|--------|
| Product listing page | Empty or shows error — no products displayed |
| Product detail pages | Fail to load — gRPC timeout errors |
| Checkout flow | Broken — cart items reference product catalog data |
| Recommendations | Fail — recommendationservice depends on productcatalogservice |
| Frontend logs | Flooded with gRPC `Unavailable` and `connection refused` errors |
| ALB health checks | Frontend still responds (HTTP 200) but with degraded content |
| NLB health checks (C2) | Fail — no healthy targets behind the NLB |
| PrivateLink | Endpoint stays `available` but traffic gets no response |

## Manual Fault Simulation Steps

### Prerequisites

- Both EKS clusters (C1 and C2) are running
- Online Boutique is deployed on both clusters
- kubectl is configured with contexts `c1` and `c2`
- ALB DNS endpoint is accessible in browser

### Step 1: Verify Normal Operation

Open the ALB URL in your browser and confirm products are displayed.

```bash
# Get ALB URL
kubectl get svc frontend-external -n online-boutique --context=c1

# Verify pods are running in both clusters
kubectl get pods -n online-boutique --context=c1
kubectl get pods -n online-boutique --context=c2
```

Expected: Frontend shows product catalog, all pods are Running.

### Step 2: Stop the Backend (productcatalogservice in C2)

Scale the deployment to zero replicas. This tells Kubernetes "I want zero pods" so it will NOT auto-restart them.

```bash
kubectl scale deployment productcatalogservice -n online-boutique --context=c2 --replicas=0
```

Verify it's down:

```bash
kubectl get pods -n online-boutique --context=c2
```

Expected: No productcatalogservice pods running. Other C2 pods (if any) unaffected.

### Step 3: Observe Frontend Degradation

1. **Refresh the ALB URL in your browser**
   - The homepage may still load (HTML/CSS served by frontend)
   - Product listings will be empty or show an error message
   - Product detail pages will fail to load
   - The storefront is effectively broken without product data

2. **Check frontend logs for gRPC errors**

```bash
kubectl logs -l app=frontend -n online-boutique --context=c1 --tail=100
```

Expected log entries:
```
rpc error: code = Unavailable desc = connection refused
failed to get product #XXXXXXXXX: rpc error: code = Unavailable
could not retrieve products: rpc error: code = DeadlineExceeded
```

These errors prove the frontend is actively trying to reach productcatalogservice through PrivateLink and failing.

### Step 4: Verify via AWS Console

#### 4a. EKS Console — Pod Status

- **C2 cluster** (us-west-2): `https://us-west-2.console.aws.amazon.com/eks/home?region=us-west-2#/clusters`
  - Navigate to: Cluster → Resources → Pods → namespace `online-boutique`
  - productcatalogservice pod will be absent (0 replicas)

- **C1 cluster** (us-east-1): `https://us-east-1.console.aws.amazon.com/eks/home?region=us-east-1#/clusters`
  - Navigate to: Cluster → Resources → Pods → namespace `online-boutique`
  - Frontend pod is still Running but serving degraded content

#### 4b. CloudWatch — NLB Metrics

- **C2 NLB**: `https://us-west-2.console.aws.amazon.com/cloudwatch/home?region=us-west-2#metricsV2:graph=~()`
  - Search for `NetworkELB` → `UnHealthyHostCount`
  - This metric will spike to 2 (both targets unhealthy) when productcatalogservice is down
  - `HealthyHostCount` drops to 0

#### 4c. CloudWatch — ALB Metrics

- **C1 ALB**: `https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#metricsV2:graph=~()`
  - Search for `ApplicationELB` → `HTTPCode_Target_5XX_Count`
  - 5xx errors may appear if the frontend returns server errors for product-dependent pages
  - `RequestCount` continues (frontend still receives traffic, just can't serve products)

#### 4d. VPC PrivateLink — Endpoint Status

- **C1 VPC Endpoint**: `https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#Endpoints:`
  - Status remains `available` — PrivateLink itself is fine
  - The issue is the backend service behind it is down, not the network path

- **C2 Endpoint Service**: `https://us-west-2.console.aws.amazon.com/vpcconsole/home?region=us-west-2#EndpointServices:`
  - Status remains `available`
  - NLB targets are unhealthy but the service endpoint still exists

#### 4e. WAF Dashboard

- **WAF**: `https://us-east-1.console.aws.amazon.com/wafv2/homev2/web-acls?region=us-east-1`
  - WAF continues to process requests normally
  - Request metrics show traffic still flowing to the ALB
  - WAF is unaware of the backend failure — it only inspects incoming HTTP requests

### Step 5: Restore the Backend

```bash
kubectl scale deployment productcatalogservice -n online-boutique --context=c2 --replicas=1
```

Verify recovery:

```bash
# Watch pod come back up
kubectl get pods -n online-boutique --context=c2 -w

# Check frontend logs — errors should stop
kubectl logs -l app=frontend -n online-boutique --context=c1 --tail=20
```

Refresh the ALB URL — products should reappear within 1-2 minutes.

### Step 6: Alternative — Complete C2 Cluster Shutdown

For a more dramatic demonstration, you can stop the entire C2 cluster's node group:

```bash
# Scale C2 node group to 0 via AWS CLI
aws eks update-nodegroup-config \
  --cluster-name obs-challenge-c2 \
  --nodegroup-name <nodegroup-name> \
  --scaling-config minSize=0,maxSize=1,desiredSize=0 \
  --region us-west-2
```

This stops ALL C2 workloads, not just productcatalogservice. The impact is the same for the frontend but more visible in monitoring dashboards.

To restore:
```bash
aws eks update-nodegroup-config \
  --cluster-name obs-challenge-c2 \
  --nodegroup-name <nodegroup-name> \
  --scaling-config minSize=2,maxSize=3,desiredSize=2 \
  --region us-west-2
```

## Summary of Evidence

| Evidence | Where to Find It |
|----------|-----------------|
| Frontend shows no products | Browser — ALB URL |
| gRPC errors in frontend logs | `kubectl logs -l app=frontend --context=c1` |
| productcatalogservice pod absent | EKS Console → C2 → Pods |
| NLB unhealthy targets | CloudWatch → NetworkELB → UnHealthyHostCount |
| ALB 5xx errors | CloudWatch → ApplicationELB → HTTPCode_Target_5XX_Count |
| PrivateLink still available | VPC Console → Endpoints (status: available) |
| System auto-recovers | Scale replicas back to 1, products reappear |

## Key Takeaway

The frontend in C1 cannot function without the productcatalogservice in C2. The cross-cluster communication via PrivateLink is the real, sole path for product data. There is no caching, no fallback, and no local copy of the product catalog in C1. When C2 is down, the storefront is broken. When C2 comes back, the storefront recovers automatically.
