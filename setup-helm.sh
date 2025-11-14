#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Prometheus Remote Write Demo Setup (Helm)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo -e "${RED}Error: kind is not installed${NC}"
    echo "Please install kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: helm is not installed${NC}"
    echo "Please install helm: https://helm.sh/docs/intro/install/"
    exit 1
fi

echo -e "${YELLOW}Step 1/8: Adding Prometheus Helm repo...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
echo ""

echo -e "${YELLOW}Step 2/8: Creating hub cluster...${NC}"
kind create cluster --config clusters/hub-cluster.yaml
echo ""

echo -e "${YELLOW}Step 3/8: Creating spoke1 cluster...${NC}"
kind create cluster --config clusters/spoke1-cluster.yaml
echo ""

echo -e "${YELLOW}Step 4/8: Creating spoke2 cluster...${NC}"
kind create cluster --config clusters/spoke2-cluster.yaml
echo ""

echo -e "${YELLOW}Step 5/8: Installing Prometheus on hub cluster...${NC}"
kubectl config use-context kind-hub
helm install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --create-namespace \
  --values values/hub-values.yaml
echo "Waiting for Prometheus to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/prometheus-server -n monitoring
echo ""

echo -e "${YELLOW}Step 6/8: Installing Prometheus + node-exporter on spoke1...${NC}"
kubectl config use-context kind-spoke1
# Replace CLUSTER_NAME with spoke1
sed 's/CLUSTER_NAME/spoke1/g' values/spoke-values.yaml > /tmp/spoke1-values.yaml
helm install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --create-namespace \
  --values /tmp/spoke1-values.yaml
echo "Waiting for Prometheus to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/prometheus-server -n monitoring
echo "Waiting for node-exporter to be ready..."
kubectl wait --for=condition=ready --timeout=60s pod -l app.kubernetes.io/name=prometheus-node-exporter -n monitoring
rm /tmp/spoke1-values.yaml
echo ""

echo -e "${YELLOW}Step 7/8: Installing Prometheus + node-exporter on spoke2...${NC}"
kubectl config use-context kind-spoke2
# Replace CLUSTER_NAME with spoke2
sed 's/CLUSTER_NAME/spoke2/g' values/spoke-values.yaml > /tmp/spoke2-values.yaml
helm install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --create-namespace \
  --values /tmp/spoke2-values.yaml
echo "Waiting for Prometheus to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/prometheus-server -n monitoring
echo "Waiting for node-exporter to be ready..."
kubectl wait --for=condition=ready --timeout=60s pod -l app.kubernetes.io/name=prometheus-node-exporter -n monitoring
rm /tmp/spoke2-values.yaml
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Access the Hub Prometheus UI:${NC}"
echo "  http://localhost:9090"
echo ""
echo -e "${YELLOW}Verify node-exporter is being scraped (agent mode - status pages only):${NC}"
echo "  Spoke1: http://localhost:9091/targets"
echo "  Spoke2: http://localhost:9092/targets"
echo ""
echo -e "${YELLOW}Example queries on hub (http://localhost:9090):${NC}"
echo "  - All node CPU metrics: node_cpu_seconds_total"
echo "  - CPU by cluster: node_cpu_seconds_total{cluster=\"spoke1\"}"
echo "  - CPU utilization: 100 - (avg by(cluster) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
echo ""
echo -e "${YELLOW}Manage Helm releases:${NC}"
echo "  - List releases: helm list -A"
echo "  - Upgrade: helm upgrade prometheus prometheus-community/prometheus -n monitoring --values values/hub-values.yaml"
echo "  - Uninstall: helm uninstall prometheus -n monitoring"
echo ""
echo -e "${YELLOW}Switch between clusters:${NC}"
echo "  kubectl config use-context kind-hub"
echo "  kubectl config use-context kind-spoke1"
echo "  kubectl config use-context kind-spoke2"
echo ""
