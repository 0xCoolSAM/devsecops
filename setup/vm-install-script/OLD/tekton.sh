#!/usr/bin/env bash
set -e

########################################
# DO NOT RUN AS ROOT
########################################
if [ "$EUID" -eq 0 ]; then
  echo "❌ Do NOT run this script with sudo"
  exit 1
fi

########################################
# VARIABLES
########################################
TEKTON_NS="tekton-pipelines"
EMAIL="hossamibraheem2014@gmail.com"

########################################
# Detect Public IP + nip.io hostname
########################################
PUBLIC_IP=$(curl -s ifconfig.me)
NIP_IP=$(echo $PUBLIC_IP | tr '.' '-')
TEKTON_HOST="tekton-${NIP_IP}.nip.io"

echo "========================================="
echo " Public IP: $PUBLIC_IP"
echo " Domain: $TEKTON_HOST"
echo "========================================="

########################################
# Install NGINX Ingress (hostNetwork)
########################################
echo "[1/8] Installing NGINX Ingress..."

kubectl create namespace ingress-nginx 2>/dev/null || true

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.hostNetwork=true \
  --set controller.kind=DaemonSet \
  --set controller.service.enabled=false \
  --set controller.admissionWebhooks.enabled=false

kubectl rollout status daemonset ingress-nginx-controller -n ingress-nginx --timeout=300s

########################################
# Install cert-manager (if not exists)
########################################
echo "[2/8] Installing cert-manager..."

if ! kubectl get namespace cert-manager >/dev/null 2>&1; then
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
fi

kubectl wait --for=condition=available deployment/cert-manager -n cert-manager --timeout=300s

########################################
# Create ClusterIssuer (idempotent)
########################################
echo "[3/8] Creating ClusterIssuer..."

cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-http
spec:
  acme:
    email: ${EMAIL}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-http-key
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

########################################
# Install Tekton Pipelines
########################################
echo "[4/8] Installing Tekton Pipelines..."

kubectl create namespace $TEKTON_NS 2>/dev/null || true

kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
kubectl wait --for=condition=Established crd/pipelineruns.tekton.dev --timeout=180s
kubectl wait --for=condition=available deployment tekton-pipelines-webhook -n $TEKTON_NS --timeout=300s

########################################
# Install Tekton Dashboard
########################################
echo "[5/8] Installing Tekton Dashboard..."

kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release-full.yaml
kubectl wait --for=condition=available deployment tekton-dashboard -n $TEKTON_NS --timeout=300s

########################################
# Fix Dashboard RBAC
########################################
echo "[6/8] Fixing Dashboard RBAC..."

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tekton-dashboard-discovery
rules:
- nonResourceURLs:
  - "/api"
  - "/api/*"
  - "/apis"
  - "/apis/*"
  verbs: ["get"]
EOF

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-dashboard-discovery
subjects:
- kind: ServiceAccount
  name: tekton-dashboard
  namespace: $TEKTON_NS
roleRef:
  kind: ClusterRole
  name: tekton-dashboard-discovery
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl rollout restart deployment tekton-dashboard -n $TEKTON_NS

########################################
# Create HTTPS Ingress
########################################
echo "[7/8] Creating HTTPS Ingress..."

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tekton-dashboard
  namespace: $TEKTON_NS
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-http
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/hsts: "true"
    nginx.ingress.kubernetes.io/hsts-max-age: "31536000"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - ${TEKTON_HOST}
      secretName: tekton-tls
  rules:
    - host: ${TEKTON_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: tekton-dashboard
                port:
                  number: 9097
EOF

########################################
# Wait for Certificate
########################################
# echo "[8/8] Waiting for TLS certificate..."

# kubectl wait --for=condition=Ready certificate/tekton-tls \
#   -n $TEKTON_NS \
#   --timeout=300s || true

########################################
# Certificate Health Check + Retry Logic
########################################
MAX_RETRIES=5
SLEEP_SECONDS=15
retry=0

echo "Starting forced retry logic (max ${MAX_RETRIES} attempts)..."

while [ $retry -lt $MAX_RETRIES ]; do

    echo "Attempt $((retry+1))..."

    STATUS=$(kubectl get certificate tekton-tls -n $TEKTON_NS \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

    if [ "$STATUS" == "True" ]; then
        echo "✅ Certificate is Ready!"
        break
    fi

    echo "❌ Certificate not Ready — deleting and retrying..."

    kubectl delete certificate tekton-tls -n $TEKTON_NS --ignore-not-found
    kubectl delete secret tekton-tls -n $TEKTON_NS --ignore-not-found

    sleep $SLEEP_SECONDS

    retry=$((retry+1))
done

########################################
# Final Result
########################################

FINAL_STATUS=$(kubectl get certificate tekton-tls -n $TEKTON_NS \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

if [ "$FINAL_STATUS" == "True" ]; then
    echo "🎉 Tekton TLS successfully issued!"
    echo "======================================"
    echo "✅ Tekton HTTPS Ready"
    echo "👉 https://${TEKTON_HOST}"
    echo "======================================"
else
    echo "⚠ Failed after ${MAX_RETRIES} attempts."
    echo "Check:"
    echo "kubectl describe certificate tekton-tls -n $TEKTON_NS"
fi