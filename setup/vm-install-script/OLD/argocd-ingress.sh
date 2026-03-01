#!/usr/bin/env bash
set -e

########################################
# Detect Public IP + nip.io hostname
########################################
PUBLIC_IP=$(curl -s ifconfig.me)
NIP_IP=$(echo $PUBLIC_IP | tr '.' '-')
DOMAIN="argocd-${NIP_IP}.nip.io"
Email="hossamibraheem2014@gmail.com"

MAX_RETRIES=5
SLEEP_SECONDS=15

ARGOCD_TLS="argocd-tls"
ARGOCD_NS="argocd"

retry=0


echo "Public IP: $PUBLIC_IP"
echo "Domain: $DOMAIN"

if ! kubectl get namespace cert-manager >/dev/null 2>&1; then
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
fi

########################################
# Install NGINX Ingress (hostNetwork)
########################################
kubectl create namespace ingress-nginx 2>/dev/null || true

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
helm repo update >/dev/null

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.hostNetwork=true \
  --set controller.kind=DaemonSet \
  --set controller.service.enabled=false \
  --set controller.admissionWebhooks.enabled=false

kubectl rollout status daemonset ingress-nginx-controller -n ingress-nginx --timeout=300s

########################################
# Install cert-manager
########################################
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

echo "Waiting for cert-manager components..."

kubectl wait --for=condition=available deployment/cert-manager -n cert-manager --timeout=300s
kubectl wait --for=condition=available deployment/cert-manager-webhook -n cert-manager --timeout=300s
kubectl wait --for=condition=available deployment/cert-manager-cainjector -n cert-manager --timeout=300s

kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=webhook -n cert-manager --timeout=300s

# Extra safety delay for webhook service
sleep 10
########################################
# Create ClusterIssuer
########################################
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-http
spec:
  acme:
    email: ${Email}
    #Prod
    server: https://acme-v02.api.letsencrypt.org/directory
    #Stage
    #server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-http-key
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

########################################
# Install ArgoCD (ClusterIP)
########################################
kubectl create ns argocd 2>/dev/null || true

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update >/dev/null

helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  --set server.service.type=ClusterIP \
  --set server.extraArgs="{--insecure}"

kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

########################################
# Create Ingress for ArgoCD
########################################
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd
  namespace: argocd
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-http
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/hsts: "true"
    nginx.ingress.kubernetes.io/hsts-max-age: "31536000"
    nginx.ingress.kubernetes.io/hsts-include-subdomains: "true"
    nginx.ingress.kubernetes.io/hsts-preload: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - ${DOMAIN}
    secretName: argocd-tls
  rules:
  - host: ${DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF

########################################
# Wait for Certificate
########################################
# echo "Waiting for TLS certificate..."
# kubectl wait --for=condition=Ready certificate/argocd-tls -n argocd --timeout=300s || true

########################################
# Certificate Health Check + Retry Logic
########################################

retry=0

echo "Starting forced retry logic (max ${MAX_RETRIES} attempts)..."

while [ $retry -lt $MAX_RETRIES ]; do

    echo "Attempt $((retry+1))..."

    STATUS=$(kubectl get certificate $ARGOCD_TLS -n $ARGOCD_NS \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

    if [ "$STATUS" == "True" ]; then
        echo "✅ Certificate is Ready!"
        break
    fi

    echo "❌ Certificate not Ready — deleting and retrying..."

    kubectl delete certificate $ARGOCD_TLS -n $ARGOCD_NS --ignore-not-found
    kubectl delete secret $ARGOCD_TLS -n $ARGOCD_NS --ignore-not-found

    sleep $SLEEP_SECONDS

    retry=$((retry+1))
done



########################################
# Final Result
########################################

FINAL_STATUS=$(kubectl get certificate $ARGOCD_TLS -n $ARGOCD_NS \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

if [ "$FINAL_STATUS" != "True" ]; then
    echo "⚠ Certificate not issued after retries."
else
    echo ""
    echo "=========================================="
    echo " ArgoCD is Ready"
    echo
    echo " URL: https://${DOMAIN}"
    echo
    echo -n " Username: admin"
    echo
    echo -n " Password: "
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
    echo
    echo "=========================================="
fi