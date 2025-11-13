# Prometheus Remote Write Demo

This repository demonstrates how to configure Prometheus using remote write with a hub-and-spoke architecture. It sets up 1 hub cluster and 2 spoke clusters using Kind (Kubernetes in Docker), where spoke clusters forward metrics to the hub cluster using Prometheus remote write.

## Architecture

```
┌─────────────────┐
│   Hub Cluster   │
│                 │
│  Prometheus     │◄─────┐
│  (Storage +     │      │
│   Query)        │      │ Remote Write
│                 │      │
└─────────────────┘      │
                         │
        ┌────────────────│
        │                │
        │                │
┌───────▼──────┐  ┌──────▼───────┐
│ Spoke1       │  │ Spoke2       │
│              │  │              │
│ Prometheus   │  │ Prometheus   │
│ (Agent Mode) │  │ (Agent Mode) │
│      +       │  │      +       │
│ node-exporter│  │ node-exporter│
└──────────────┘  └──────────────┘
```

## Features

- **Hub Cluster**: Centralized Prometheus for storing and querying all metrics
- **Spoke Clusters**: Prometheus agents that scrape local metrics and forward to hub
- **Agent Mode**: Spoke Prometheus instances run in agent mode (no local storage, forward-only)
- **Node Exporter**: Collects node-level CPU metrics from each spoke cluster
- **Simple Setup**: Single script to provision all clusters

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Quick Start

### Setup

Run the setup script to create all clusters and deploy Prometheus:

```bash
./setup.sh
```

This will:
1. Create 3 Kind clusters (hub, spoke1, spoke2)
2. Deploy Prometheus to the hub cluster with remote write receiver enabled
3. Deploy node-exporter to spoke clusters
4. Deploy Prometheus agents to spoke clusters (configured to remote write to hub)

### Access Prometheus UI

Once setup is complete, access the hub Prometheus UI:

- **Hub**: http://localhost:9090

**Note**: This is your main interface for querying all metrics. Spoke Prometheus instances run in agent mode and do not have a functional query UI. They only forward metrics to the hub.

### Verify Node-Exporter is Running

Check that node-exporter is being scraped by the spoke Prometheus agents:

- **Spoke1**: http://localhost:9091/targets (should show node-exporter endpoint as UP)
- **Spoke2**: http://localhost:9092/targets (should show node-exporter endpoint as UP)

**Note**: The spoke clusters run in agent mode, so only the status pages (like /targets) are available. The query UI is disabled.

### Verify Remote Write is Working

1. Open the hub Prometheus UI: http://localhost:9090
2. Go to **Status → Targets** to verify the hub is scraping itself
3. Run a query to see metrics from spoke clusters:

```promql
node_cpu_seconds_total
```

You should see metrics with `cluster="spoke1"` and `cluster="spoke2"` labels.

### Example Queries

Run these queries on the hub (http://localhost:9090):

**View all node CPU metrics:**
```promql
node_cpu_seconds_total
```

**View metrics from specific spoke:**
```promql
node_cpu_seconds_total{cluster="spoke1"}
```

**Calculate CPU utilization by cluster:**
```promql
100 - (avg by(cluster) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**Find clusters with >70% CPU utilization:**
```promql
100 - (avg by(cluster) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 70
```

**Find clusters with sustained >70% CPU over 5 minutes:**
```promql
min_over_time(
  (100 - (avg by(cluster) (rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100))[5m:]
) > 70
```

### Switch Between Clusters

Use kubectl to interact with different clusters:

```bash
# Switch to hub cluster
kubectl config use-context kind-hub

# Switch to spoke1 cluster
kubectl config use-context kind-spoke1

# Switch to spoke2 cluster
kubectl config use-context kind-spoke2
```

### Teardown

Delete all clusters:

```bash
kind delete clusters --all
```

## Configuration Details

### Hub Prometheus

- **Location**: `manifests/hub-prometheus.yaml`
- **Mode**: Full Prometheus with storage and querying
- **Remote Write Receiver**: Enabled via `--web.enable-remote-write-receiver` flag
- **Port**: Exposed on localhost:9090

### Spoke Prometheus

- **Location**: `manifests/spoke-prometheus.yaml`
- **Mode**: Agent mode via `--enable-feature=agent` flag
- **Function**: Scrapes node-exporter and forwards to hub
- **Remote Write Target**: `http://host.docker.internal:9090/api/v1/write`
- **External Labels**: Each spoke has `cluster: "spoke1"` or `cluster: "spoke2"` label

### Node Exporter

- **Location**: `manifests/node-exporter.yaml`
- **Deployment**: DaemonSet (runs on every node)
- **Metrics**: Collects OS-level metrics including CPU, memory, disk, network
- **Port**: 9100

## Production Considerations

### GPU Metrics (dcgm-exporter)

For clusters with NVIDIA GPUs, you would also deploy [dcgm-exporter](https://github.com/NVIDIA/dcgm-exporter) to collect GPU metrics.

Add a second scrape config to `manifests/spoke-prometheus.yaml`:

```yaml
scrape_configs:
  - job_name: 'node-exporter'
    # ... existing config

  - job_name: 'dcgm-exporter'
    kubernetes_sd_configs:
      - role: endpoints
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_name]
        action: keep
        regex: dcgm-exporter
      - source_labels: [__meta_kubernetes_endpoint_port_name]
        action: keep
        regex: metrics
      - source_labels: [__meta_kubernetes_pod_node_name]
        target_label: node
```

### Filtering Metrics

To reduce data volume and only send CPU metrics, uncomment the `metric_relabel_configs` section in `manifests/spoke-prometheus.yaml`:

```yaml
metric_relabel_configs:
  - source_labels: [__name__]
    regex: 'node_cpu_seconds_total|node_cpu_guest_seconds_total'
    action: keep
```

## Troubleshooting

### Metrics not appearing in hub

1. Check spoke Prometheus logs:
   ```bash
   kubectl config use-context kind-spoke1
   kubectl logs -n monitoring deployment/prometheus
   ```

2. Look for remote write errors in the logs

3. Verify hub Prometheus is receiving writes:
   ```bash
   kubectl config use-context kind-hub
   kubectl logs -n monitoring deployment/prometheus | grep "remote_write"
   ```

### Cannot access Prometheus UIs

Verify the NodePort services are running:

```bash
kubectl config use-context kind-hub
kubectl get svc -n monitoring
```

Check that port mappings are configured in Kind cluster configs.

## References

- [Prometheus Remote Write Specification](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#remote_write)
- [Prometheus Agent Mode](https://prometheus.io/blog/2021/11/16/agent/)
- [Node Exporter](https://github.com/prometheus/node_exporter)
- [Kind Documentation](https://kind.sigs.k8s.io/)
