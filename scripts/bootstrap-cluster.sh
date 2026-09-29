#!/bin/bash
# Bootstrap a new Kapsule cluster with required cluster-level components.
# Run once after terraform creates the cluster.
#
# Prerequisites:
#   - kubectl configured for the target cluster
#   - helm 3 installed
#
# Usage:
#   ./scripts/bootstrap-cluster.sh [staging|prod]
set -euo pipefail

# This legacy stack uses a retired ingress controller. Require deliberate opt-in
# for reproduction; production deployments must migrate to a maintained controller.
if [ "${SCIATH_ALLOW_RETIRED_INGRESS:-0}" != "1" ]; then
  echo "Ingress NGINX is retired. Migrate ingress before a new production deployment." >&2
  echo "For legacy reproduction only, set SCIATH_ALLOW_RETIRED_INGRESS=1." >&2
  exit 1
fi

TARGET_ENV="${1:-staging}"
case "$TARGET_ENV" in
  staging|prod) ;;
  *) echo "Usage: $0 [staging|prod]" >&2; exit 1 ;;
esac
echo "=== Bootstrapping Kapsule cluster for: $TARGET_ENV ==="

# 1. ingress-nginx
echo "--- Installing ingress-nginx ---"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --version 4.15.1 \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/scw-loadbalancer-type"=LB-S \
  --wait

# 2. cert-manager
echo "--- Installing cert-manager ---"
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --version v1.21.2 \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait

# 3. sealed-secrets
echo "--- Installing sealed-secrets ---"
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets 2>/dev/null || true
helm repo update
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --version 2.20.0 \
  --namespace kube-system \
  --wait

# 4. Apply ClusterIssuers
echo "--- Applying cert-manager ClusterIssuers ---"
kubectl apply -f k8s/base/ingress/cluster-issuer.yaml

# 5. Create namespace
echo "--- Creating sciath namespace ---"
kubectl apply -f k8s/base/namespace.yaml

# 6. Backup sealed-secrets key
echo ""
echo "=== IMPORTANT: Backup the sealed-secrets key ==="
echo "Run this to export the sealing key (store securely):"
echo ""
echo "  kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealing-key-backup.yaml"
echo ""
echo "Store this backup in Scaleway Secret Manager or a secure vault."
echo "Without it, a cluster rebuild will require re-sealing all secrets."

# 7. Print LB IP
echo ""
echo "=== Load Balancer IP ==="
echo "Waiting for external IP..."
for _ in $(seq 1 30); do
  LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [ -n "$LB_IP" ]; then
    echo "Load Balancer IP: $LB_IP"
    echo ""
    echo "Point your DNS records to this IP:"
    if [ "$TARGET_ENV" = "prod" ]; then
      echo "  api.sciath.io -> $LB_IP"
    else
      echo "  api-staging.sciath.io -> $LB_IP"
    fi
    break
  fi
  sleep 5
done

echo ""
echo "=== Bootstrap complete ==="
echo ""
echo "Next steps:"
echo "  1. Create the image pull secret:"
echo "     kubectl create secret docker-registry scw-registry \\"
echo "       --namespace sciath \\"
echo "       --docker-server=rg.fr-par.scw.cloud \\"
echo "       --docker-username=nologin \\"
echo "       --docker-password=\$SCW_SECRET_KEY"
echo ""
echo "  2. Seal your secrets:"
echo "     kubectl create secret generic sciath-secrets \\"
echo "       --namespace sciath --from-literal=SECRET_KEY=... \\"
echo "       --dry-run=client -o yaml | kubeseal --format yaml > k8s/base/secrets/sealedsecret.yaml"
echo ""
echo "  3. Deploy:"
echo "     cd k8s/overlays/$TARGET_ENV && kustomize build . | kubectl apply -f -"
