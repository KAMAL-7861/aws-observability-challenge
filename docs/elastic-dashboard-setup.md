# Elastic Dashboard & Alert Setup Guide

## Prerequisites
1. Sign up for [Elastic Cloud free trial](https://cloud.elastic.co/registration)
2. Create a deployment (select closest region)
3. Note your **Cloud ID**, **Fleet Server URL**, and **Enrollment Token**
4. Update `k8s/c1/elastic-agent/configmap.yaml` and `k8s/c2/elastic-agent/configmap.yaml` with these values

## Fleet Server Configuration
1. In Kibana → Fleet → Settings, verify Fleet Server URL is correct
2. Create an Agent Policy named `obs-challenge-policy`
3. Add the **Kubernetes** integration to the policy:
   - Enable: Container logs, Pod metrics, Node metrics, Event collection
   - Set namespace to `online-boutique`
4. Generate an enrollment token for this policy
5. Update ConfigMaps with the enrollment token

## Dashboard 1: Cross-Cluster Service Health

### Create in Kibana → Dashboards → Create Dashboard

**Panel 1 — Pod Status by Cluster**
- Visualization: Data Table
- Index: `metrics-kubernetes.pod-*`
- Rows: `kubernetes.pod.name`, `kubernetes.node.name`
- Columns: `kubernetes.pod.status.phase`
- Filter: `kubernetes.namespace: online-boutique`
- Split by: `CLUSTER_NAME` field

**Panel 2 — Pod Restart Count**
- Visualization: Lens (Bar chart)
- Index: `metrics-kubernetes.container-*`
- Y-axis: Max of `kubernetes.container.status.restarts`
- X-axis: `kubernetes.pod.name`
- Filter: `kubernetes.namespace: online-boutique`
- Break down by: `CLUSTER_NAME`

**Panel 3 — Node CPU Utilization**
- Visualization: Lens (Line chart)
- Index: `metrics-kubernetes.node-*`
- Y-axis: Average of `kubernetes.node.cpu.usage.nanocores`
- X-axis: `@timestamp`
- Break down by: `kubernetes.node.name`

**Panel 4 — Node Memory Utilization**
- Visualization: Lens (Line chart)
- Index: `metrics-kubernetes.node-*`
- Y-axis: Average of `kubernetes.node.memory.usage.bytes`
- X-axis: `@timestamp`
- Break down by: `kubernetes.node.name`

## Dashboard 2: Application Request Metrics

**Panel 1 — Frontend Request Logs**
- Visualization: Lens (Line chart)
- Index: `logs-kubernetes.container_logs-*`
- Filter: `kubernetes.container.name: frontend`
- Y-axis: Count
- X-axis: `@timestamp` (1-minute intervals)

**Panel 2 — Error Rate (5xx in frontend)**
- Visualization: Lens (Line chart)
- Index: `logs-kubernetes.container_logs-*`
- Filter: `kubernetes.container.name: frontend AND message: *error*`
- Y-axis: Count
- X-axis: `@timestamp`

**Panel 3 — productcatalogservice Logs (C2)**
- Visualization: Log stream
- Index: `logs-kubernetes.container_logs-*`
- Filter: `kubernetes.container.name: productcatalogservice AND CLUSTER_NAME: obs-challenge-c2`

## Example Log Queries

### Frontend logs (C1):
```
kubernetes.container.name: "frontend" AND CLUSTER_NAME: "obs-challenge-c1"
```

### productcatalogservice logs (C2):
```
kubernetes.container.name: "productcatalogservice" AND CLUSTER_NAME: "obs-challenge-c2"
```

### Cross-cluster error correlation:
```
(kubernetes.container.name: "frontend" AND message: *productcatalog* AND message: *error*) OR (kubernetes.container.name: "productcatalogservice" AND message: *error*)
```
