# Live Demo Script

## Pre-Demo Checklist
- [ ] Both EKS clusters running (`kubectl get nodes --context=obs-challenge-c1` and `--context=obs-challenge-c2`)
- [ ] All pods healthy (`kubectl get pods -n online-boutique --context=obs-challenge-c1`)
- [ ] productcatalogservice running in C2 (`kubectl get pods -n online-boutique --context=obs-challenge-c2`)
- [ ] ALB DNS accessible in browser
- [ ] Elastic Cloud dashboard open in browser
- [ ] Terminal ready with kubectl contexts configured

## Demo Flow (15-20 minutes)

### Step 1: Show the Running Application (2 min)

```bash
# Get ALB DNS
terraform -chdir=terraform/environments/c1-us-east-1 output -raw alb_dns_name

# Open in browser — show product listings loading (data from C2 via PrivateLink)
# Click around: browse products, add to cart, show checkout flow
```

**Talking point**: "Products you see here are served by productcatalogservice running in us-west-2, fetched via PrivateLink cross-region."

### Step 2: Show Infrastructure State (3 min)

```bash
# Show both clusters
kubectl get nodes --context=obs-challenge-c1
kubectl get nodes --context=obs-challenge-c2

# Show pods in C1 (all services except productcatalogservice)
kubectl get pods -n online-boutique --context=obs-challenge-c1

# Show pods in C2 (only productcatalogservice)
kubectl get pods -n online-boutique --context=obs-challenge-c2

# Show the ExternalName service pointing to VPC Endpoint
kubectl get svc productcatalogservice-external -n online-boutique --context=obs-challenge-c1 -o yaml
```

### Step 3: Prove PrivateLink is Working (2 min)

```bash
# Show VPC Endpoint state
aws ec2 describe-vpc-endpoints --region us-east-1 \
  --query 'VpcEndpoints[?ServiceName!=`null`].{ID:VpcEndpointId,State:State,DNS:DnsEntries[0].DnsName}' \
  --output table

# Show VPC Endpoint Service state
aws ec2 describe-vpc-endpoint-services --region us-west-2 \
  --query 'ServiceDetails[?ServiceType[0].ServiceType==`Interface`].{Name:ServiceName,State:ServiceState}' \
  --output table

# Test connectivity from frontend pod to productcatalogservice-external
kubectl exec -it $(kubectl get pod -n online-boutique --context=obs-challenge-c1 -l app=frontend -o jsonpath='{.items[0].metadata.name}') \
  -n online-boutique --context=obs-challenge-c1 \
  -- sh -c 'nslookup productcatalogservice-external.online-boutique.svc.cluster.local'
```

### Step 4: Show WAF State (2 min)

```bash
# Show WAF Web ACL
aws wafv2 list-web-acls --scope REGIONAL --region us-east-1 --output table

# Test WAF blocking — SQLi attempt
curl -s -o /dev/null -w "%{http_code}" "http://$(terraform -chdir=terraform/environments/c1-us-east-1 output -raw alb_dns_name)/?q=1%27%20OR%201%3D1--"
# Expected: 403

# Show WAF metrics in AWS Console (open in browser)
```

**Talking point**: "WAF returned 403 for the SQL injection attempt. Legitimate traffic gets 200."

### Step 5: Show Security Posture — Run Verification Tool (2 min)

```bash
cd verification
python verify.py \
  --c1-region us-east-1 \
  --c1-cluster obs-challenge-c1 \
  --c2-region us-west-2 \
  --c2-cluster obs-challenge-c2 \
  --output text

# Also show JSON output
python verify.py \
  --c1-region us-east-1 \
  --c1-cluster obs-challenge-c1 \
  --c2-region us-west-2 \
  --c2-cluster obs-challenge-c2 \
  --output json
```

**Expected output**: All 5 checks PASS.

### Step 6: Show Elastic Observability (3 min)

1. Open Kibana → Dashboards → Cross-Cluster Service Health
2. Show pod status across both clusters
3. Show node CPU/memory metrics
4. Show frontend request logs
5. Show productcatalogservice logs from C2
6. Point out CLUSTER_NAME metadata on log entries

### Step 7: Trigger Fault Simulation (3 min)

```bash
# Run the fault simulation
./scripts/fault-sim.sh

# Watch pod recovery in real-time
kubectl get pods -n online-boutique --context=obs-challenge-c2 -l app=productcatalogservice -w
```

**While waiting**: "The pod is being killed. Kubernetes will restart it automatically. Meanwhile, the frontend in C1 will get gRPC errors for product catalog requests."

### Step 8: Show Fault Detection in Elastic (3 min)

1. Open Kibana → Observability → Alerts
2. Show the alert that fired (Pod Restart Alert, productcatalogservice Unreachable)
3. Show the error rate spike on the dashboard
4. Show the pod restart count increase
5. Show the system recovering to normal

**Talking point**: "The fault was detected within minutes. The alert identifies the affected service, cluster, and fault type. The system self-healed via Kubernetes."

## Post-Demo Q&A Prep

**Q: Why PrivateLink instead of VPC peering?**
A: PrivateLink is unidirectional and service-oriented — only exposes port 3550, not the entire VPC. More secure for cross-region service consumption.

**Q: Why only one service in C2?**
A: productcatalogservice is the cleanest split — env var override, no code changes, direct frontend dependency. More services would add complexity without proportional value.

**Q: What about HTTPS?**
A: No custom domain available. In production, we'd add ACM certificate + HTTPS listener on the ALB.

**Q: How does this scale?**
A: Each PrivateLink endpoint can handle thousands of connections. EKS node groups can auto-scale. Elastic Cloud scales storage automatically.
