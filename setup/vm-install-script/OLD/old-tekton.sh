#!/usr/bin/env bash
set -e

########################################
# DO NOT RUN AS ROOT
########################################
if [ "$EUID" -eq 0 ]; then
  echo "❌ Do NOT run this script with sudo"
  echo "Run as normal user: ./tekton.sh"
  exit 1
fi

########################################
# VARIABLES
########################################
DOMAIN="devsecops.switzerlandnorth.cloudapp.azure.com"
TEKTON_HOST="$DOMAIN"
TEKTON_NS="tekton-pipelines"

echo "Using domain: $TEKTON_HOST"
#########################################
echo "[1/9] Preparing system packages..."
#########################################

sudo apt-get update -y
sudo apt-get install -y \
  curl \
  wget \
  git \
  jq \
  apt-transport-https \
  ca-certificates \
  gnupg \
  gnupg-agent \
  dirmngr \
  software-properties-common

########################################
# 1) Namespace
########################################
kubectl create namespace $TEKTON_NS --dry-run=client -o yaml | kubectl apply -f -


########################################
# 2) Install NGINX Ingress (bare metal)
########################################

#kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
echo "Waiting for ingress controller..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

# Force hostNetwork exposure (bare-metal behavior)
kubectl -n ingress-nginx patch deployment ingress-nginx-controller --type=json -p='[
{"op":"add","path":"/spec/template/spec/hostNetwork","value":true},
{"op":"add","path":"/spec/template/spec/dnsPolicy","value":"ClusterFirstWithHostNet"}
]'

kubectl rollout restart deploy ingress-nginx-controller -n ingress-nginx
#########################################
echo "[2/9] Installing Tekton Pipelines..."
#########################################

kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

echo "Waiting for pipelines CRDs..."
sleep 10
kubectl wait --for=condition=Established crd/pipelineruns.tekton.dev --timeout=180s

echo "Waiting for webhook..."
kubectl wait --for=condition=available deployment tekton-pipelines-webhook -n $TEKTON_NS --timeout=300s

#########################################
echo "[3/9] Installing Tekton Triggers..."
#########################################

kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml

echo "Waiting triggers webhook..."
kubectl wait --for=condition=available deployment tekton-triggers-webhook -n $TEKTON_NS --timeout=300s

#########################################
echo "[4/9] Install Tekton Dashboard (FULL VERSION!)"
########################################
echo "Installing Tekton Dashboard..."
kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release-full.yaml

echo "Waiting for dashboard..."
kubectl wait --for=condition=available deployment tekton-dashboard -n $TEKTON_NS --timeout=300s

########################################
echo "[5/9] FIX Dashboard RBAC (IMPORTANT)"
########################################
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

kubectl rollout restart deploy tekton-dashboard -n $TEKTON_NS


########################################
echo "[6/9] Create Dashboard Ingress (FINAL FIX)"
########################################
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tekton-dashboard
  namespace: $TEKTON_NS
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/use-regex: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: ${TEKTON_HOST}
    http:
      paths:

      # 1) API prefix (do NOT rewrite)
      - path: /apis(/.*)?
        pathType: ImplementationSpecific
        backend:
          service:
            name: tekton-dashboard
            port:
              number: 9097

      - path: /api(/.*)?
        pathType: ImplementationSpecific
        backend:
          service:
            name: tekton-dashboard
            port:
              number: 9097

      # 2) UI & other assets
      - path: /(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: tekton-dashboard
            port:
              number: 9097
EOF
########################################
echo "[7/9] Restart ingress controller"
########################################
kubectl delete pod -n ingress-nginx -l app.kubernetes.io/component=controller || true


#########################################
echo "[8/9] Installing Tekton CLI (tkn)..."
#########################################

ARCH=$(uname -m)

case $ARCH in
  x86_64) TKN_ARCH="x86_64" ;;
  aarch64) TKN_ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

TKN_VERSION=$(curl -s https://api.github.com/repos/tektoncd/cli/releases/latest | jq -r .tag_name)

FILE="tkn_${TKN_VERSION#v}_Linux_${TKN_ARCH}.tar.gz"
URL="https://github.com/tektoncd/cli/releases/download/${TKN_VERSION}/${FILE}"

echo "Downloading $URL"

wget $URL
tar -xzf $FILE
sudo mv tkn /usr/local/bin/
sudo chmod +x /usr/local/bin/tkn
rm $FILE

echo "Tekton CLI installed:"
tkn version

########################################
echo "[9/9] Validation"
########################################
sleep 10
curl -k https://${TEKTON_HOST}/apis/tekton.dev/v1 >/dev/null && OK=1 || OK=0

echo ""
echo "======================================"
if [ "$OK" = "1" ]; then
  echo "TEKTON INSTALLED SUCCESSFULLY 🎉"
  echo "Open: https://${TEKTON_HOST}"
else
  echo "Installed but ingress still warming up..."
fi
echo "================="
echo "Try:"
echo "tkn pipeline list"
echo ""