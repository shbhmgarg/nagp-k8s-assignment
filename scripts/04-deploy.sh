#!/bin/bash
set -e

NAMESPACE=nagp-assignment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIRECTORY="$(dirname "$SCRIPT_DIR")"

echo "---- CREATING NAMESPACE ----"
kubectl apply -f "$ROOT_DIRECTORY/k8s/namespace.yaml"

echo "---- CREATING CONFIGS ----"
kubectl apply -f "$ROOT_DIRECTORY/k8s/configmap.yaml"

echo "---- CREATING SECRETS ----"
kubectl apply -f "$ROOT_DIRECTORY/k8s/secret.yaml"

echo "---- CREATING DB PERSISTENT VOLUME ----"
kubectl apply -f "$ROOT_DIRECTORY/k8s/db-pvc.yaml"

echo "---- DEPLOYING DATABASE ----"
kubectl apply -f "$ROOT_DIRECTORY/k8s/db-deployment.yaml"
kubectl apply -f "$ROOT_DIRECTORY/k8s/db-service.yaml"

echo "---- DEPLOYING API ----"
kubectl apply -f "$ROOT_DIRECTORY/k8s/api-deployment.yaml"
kubectl apply -f "$ROOT_DIRECTORY/k8s/api-service.yaml"
kubectl apply -f "$ROOT_DIRECTORY/k8s/api-hpa.yaml"
kubectl apply -f "$ROOT_DIRECTORY/k8s/ingress.yaml"

echo ""
echo "Waiting for database to be ready..."
kubectl wait --for=condition=available --timeout=180s \
  deployment/postgres -n nagp-assignment

echo ""
echo "Waiting for API pods to be ready..."
kubectl wait --for=condition=available --timeout=180s \
  deployment/nagp-api -n nagp-assignment

echo ""
echo "---- ✅✅✅✅ All resources deployed! ✅✅✅✅ ----"
echo ""
echo "Run ./scripts/05-verify.sh to check status and get the URL."