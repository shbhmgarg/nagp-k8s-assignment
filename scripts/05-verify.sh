#!/bin/bash
# Shows the state of all deployed resources and fetches the Ingress URL.

echo "==================================="
echo "All resources in 'nagp-assignment' namespace:"
echo "==================================="
kubectl get all -n nagp-assignment

echo ""
echo "==================================="
echo "PersistentVolumeClaims:"
echo "==================================="
kubectl get pvc -n nagp-assignment

echo ""
echo "==================================="
echo "ConfigMaps and Secrets:"
echo "==================================="
kubectl get configmap,secret -n nagp-assignment

echo ""
echo "==================================="
echo "HPA status:"
echo "==================================="
kubectl get hpa -n nagp-assignment

echo ""
echo "==================================="
echo "Ingress external IP:"
echo "==================================="
INGRESS_IP=$(kubectl get ingress nagp-ingress -n nagp-assignment -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ -z "$INGRESS_IP" ]; then
  echo "Ingress IP not yet assigned. Wait 2-3 minutes and retry."
else
  echo "Ingress IP: $INGRESS_IP"
  echo ""
  echo "Test URLs:"
  echo "  http://$INGRESS_IP/"
  echo "  http://$INGRESS_IP/health"
  echo "  http://$INGRESS_IP/employees"
fi