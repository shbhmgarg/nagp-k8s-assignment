#!/bin/bash
set -e

CLUSTER_NAME="nagp-cluster"
ZONE="us-central1-a"

echo "WARNING: This will delete the cluster and all resources."
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

# Delete PVC first to ensure persistent disk is released
echo "Deleting PVC..."
kubectl delete pvc postgres-pvc -n nagp --ignore-not-found

# Delete the cluster (also deletes load balancer)
echo "Deleting cluster..."
gcloud container clusters delete "$CLUSTER_NAME" --zone "$ZONE" --quiet

# Clean up any orphaned forwarding rules
echo "Checking for orphaned load balancer resources..."
gcloud compute forwarding-rules list --format="value(name)" | while read rule; do
  if [[ "$rule" == *"nagp"* ]]; then
    gcloud compute forwarding-rules delete "$rule" --global --quiet
  fi
done

echo ""
echo "Cleanup complete."