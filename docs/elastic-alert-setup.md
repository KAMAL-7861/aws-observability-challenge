# Elastic Alert Configuration Guide

## Alert 1: Pod Restart Count > 2 in 5 Minutes

### Setup in Kibana → Observability → Alerts → Create Rule

- **Rule type**: Custom threshold
- **Index**: `metrics-kubernetes.container-*`
- **Condition**: MAX of `kubernetes.container.status.restarts` IS ABOVE 2
- **Group by**: `kubernetes.pod.name`
- **Time window**: 5 minutes
- **Check every**: 1 minute
- **Filter**: `kubernetes.namespace: online-boutique`
- **Action**: Log to Kibana alert index (or email/Slack if configured)
- **Alert name**: `Pod Restart Alert - Online Boutique`
- **Message template**:
  ```
  Pod {{kubernetes.pod.name}} in cluster {{CLUSTER_NAME}} has restarted
  {{kubernetes.container.status.restarts}} times in the last 5 minutes.
  ```

## Alert 2: Error Rate Spike (Frontend)

- **Rule type**: Custom threshold
- **Index**: `logs-kubernetes.container_logs-*`
- **Condition**: COUNT IS ABOVE 10
- **Filter**: `kubernetes.container.name: frontend AND message: *error*`
- **Time window**: 5 minutes
- **Check every**: 1 minute
- **Alert name**: `Frontend Error Rate Spike`
- **Message template**:
  ```
  Frontend error rate spike detected: {{count}} errors in the last 5 minutes
  in cluster {{CLUSTER_NAME}}.
  ```

## Alert 3: productcatalogservice Unreachable

- **Rule type**: Custom threshold
- **Index**: `logs-kubernetes.container_logs-*`
- **Condition**: COUNT IS ABOVE 5
- **Filter**: `kubernetes.container.name: frontend AND message: *productcatalog* AND (message: *unavailable* OR message: *connection refused* OR message: *deadline exceeded*)`
- **Time window**: 5 minutes
- **Check every**: 1 minute
- **Alert name**: `productcatalogservice Unreachable`
- **Message template**:
  ```
  productcatalogservice appears unreachable from frontend in cluster
  {{CLUSTER_NAME}}. {{count}} connection errors in the last 5 minutes.
  Check PrivateLink connectivity and C2 pod health.
  ```

## Expected Metric Baselines

| Metric | Normal Value | Alert Threshold |
|--------|-------------|-----------------|
| Pod restart count (5 min) | 0 | > 2 |
| Frontend error count (5 min) | < 5 | > 10 |
| productcatalog connection errors (5 min) | 0 | > 5 |
| Node CPU usage | < 60% | > 80% |
| Node memory usage | < 70% | > 85% |

## Verifying Alerts Work

1. Trigger the fault simulation: `./scripts/fault-sim.sh`
2. Wait 5-10 minutes
3. Check Kibana → Observability → Alerts
4. You should see:
   - `Pod Restart Alert` for productcatalogservice in C2
   - `productcatalogservice Unreachable` from frontend in C1
   - Possibly `Frontend Error Rate Spike` if enough requests hit during the outage
