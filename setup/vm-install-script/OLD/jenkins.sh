#!/usr/bin/env bash
set -e

MAX_RETRIES=5
SLEEP_SECONDS=15

TLS="jenkins-tls"
JENKINS_NS="jenkins"

retry=0

########################################
# Detect Public IP
########################################
PUBLIC_IP=$(curl -s ifconfig.me)
NIP_IP=$(echo $PUBLIC_IP | tr '.' '-')
DOMAIN="jenkins-${NIP_IP}.nip.io"
EMAIL="hossamibraheem2014@gmail.com"

echo "Public IP: $PUBLIC_IP"
echo "Domain: $DOMAIN"

########################################
# Jenkins
########################################
log "Installing Jenkins"

apt-get install -y openjdk-17-jdk

# remove old broken repo + keys
sudo rm -f /etc/apt/sources.list.d/jenkins.list
sudo rm -f /etc/apt/keyrings/jenkins*
sudo rm -rf /var/lib/apt/lists/*

# create keyring dir
sudo mkdir -p /etc/apt/keyrings

# install NEW official key (2026)
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

# add repo (official format)
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
 | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# update
sudo apt update

sudo apt install -y fontconfig openjdk-21-jre
sudo apt install -y jenkins
sudo systemctl enable --now jenkins
sudo systemctl start jenkins

sudo mkdir -p /root/.kube
sudo cp /etc/kubernetes/admin.conf /root/.kube/config
sudo chown root:root /root/.kube/config

########################################
# Ensure Namespace
########################################
kubectl create ns jenkins 2>/dev/null || true

########################################
# Create Service + Endpoint for external Jenkins
########################################
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: jenkins
  namespace: jenkins
spec:
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: v1
kind: Endpoints
metadata:
  name: jenkins
  namespace: jenkins
subsets:
  - addresses:
      - ip: ${PUBLIC_IP}
    ports:
      - port: 8080
EOF

########################################
# Create Ingress
########################################
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jenkins
  namespace: jenkins
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
        - ${DOMAIN}
      secretName: jenkins-tls
  rules:
    - host: ${DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: jenkins
                port:
                  number: 8080
EOF

########################################
# Certificate Health Check + Retry Logic
########################################

retry=0

echo "Starting forced retry logic (max ${MAX_RETRIES} attempts)..."

while [ $retry -lt $MAX_RETRIES ]; do

    echo "Attempt $((retry+1))..."

    STATUS=$(kubectl get certificate $TLS -n $JENKINS_NS \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

    if [ "$STATUS" == "True" ]; then
        echo "✅ Certificate is Ready!"
        break
    fi

    echo "❌ Certificate not Ready — deleting and retrying..."

    kubectl delete certificate $TLS -n $JENKINS_NS --ignore-not-found
    kubectl delete secret $TLS -n $JENKINS_NS --ignore-not-found

    sleep $SLEEP_SECONDS

    retry=$((retry+1))
done

########################################
# Final Result
########################################

FINAL_STATUS=$(kubectl get certificate $TLS -n $JENKINS_NS \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

if [ "$FINAL_STATUS" != "True" ]; then
    echo "⚠ Certificate not issued after retries."
else
    echo "===================================="
    echo " Jenkins is Ready"
    echo "https://${DOMAIN}"
    echo "Password:"
    cat /var/lib/jenkins/secrets/initialAdminPassword
    echo
fi