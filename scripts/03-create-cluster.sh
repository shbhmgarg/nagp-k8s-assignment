#!/bin/bash
set -e

CLUSTER_NAME="nagp-cluster"
ZONE="us-central1-a"

echo "Creating GKE cluster: $CLUSTER_NAME"
gcloud container clusters create "$CLUSTER_NAME" \
  --zone "$ZONE" \
  --num-nodes 2 \
  --machine-type e2-small \
  --enable-autoscaling \
  --min-nodes 1 \
  --max-nodes 3 \
  --disk-size 20 \
  --disk-type pd-standard

echo ""
echo "Connecting kubectl to cluster..."
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE"

echo ""
echo "Verifying nodes..."
kubectl get nodes

echo ""
echo "Cluster ready."