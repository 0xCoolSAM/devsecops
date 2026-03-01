#!/usr/bin/env bash
set -euo pipefail

########################################
# Helpers
########################################
log(){ echo -e "\n\033[1;32m[INFO]\033[0m $1"; }
warn(){ echo -e "\n\033[1;33m[WARN]\033[0m $1"; }

########################################
# System preparation
########################################
log "System preparation"

apt-get update -y
apt-get install -y curl ca-certificates gnupg lsb-release software-properties-common apt-transport-https

swapoff -a || true
sed -i '/swap/d' /etc/fstab || true

cat <<EOF >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay || true
modprobe br_netfilter || true

cat <<EOF >/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF
sysctl --system

########################################
# containerd
########################################
log "Installing containerd"

apt-get install -y containerd

mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' \
 > /etc/containerd/config.toml

systemctl enable containerd
systemctl restart containerd

########################################
# Kubernetes
########################################
log "Installing Kubernetes"

KVER="v1.35"

mkdir -p /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/${KVER}/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KVER}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl


########################################
# Cluster Init
########################################
log "Initializing cluster"

kubeadm reset -f || true

if [ ! -f /etc/kubernetes/admin.conf ]; then
  kubeadm init --pod-network-cidr=10.244.0.0/16 --skip-token-print
fi

mkdir -p /home/$SUDO_USER/.kube
cp /etc/kubernetes/admin.conf /home/$SUDO_USER/.kube/config
chown -R $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.kube

export KUBECONFIG=/etc/kubernetes/admin.conf

########################################
# kubectl alias
########################################
log "Adding kubectl alias"

grep -qxF "alias k=kubectl" /home/$SUDO_USER/.bashrc || \
echo "alias k=kubectl" >> /home/$SUDO_USER/.bashrc

########################################
# kubectl autocomplete (root + user)
########################################
log "Enabling kubectl autocomplete"

sudo apt-get install -y bash-completion

enable_completion() {
  TARGET_HOME=$1
  BASHRC="$TARGET_HOME/.bashrc"

  grep -qxF "source <(kubectl completion bash)" $BASHRC || \
  echo "source <(kubectl completion bash)" >> $BASHRC

  grep -qxF "alias k=kubectl" $BASHRC || \
  echo "alias k=kubectl" >> $BASHRC

  grep -qxF "complete -o default -F __start_kubectl k" $BASHRC || \
  echo "complete -o default -F __start_kubectl k" >> $BASHRC
}

# enable for original sudo user
enable_completion /home/$SUDO_USER
sudo chown $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.bashrc

# enable for root
enable_completion /root
########################################
# Network
########################################
log "Installing Flannel CNI"

kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

sleep 25
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

kubectl get nodes -o wide

# ########################################
# # Install NGINX Ingress (bare metal)
# ########################################

# #kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
# kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
# echo "Waiting for ingress controller..."
# kubectl wait --namespace ingress-nginx \
#   --for=condition=ready pod \
#   --selector=app.kubernetes.io/component=controller \
#   --timeout=300s

# # Force hostNetwork exposure (bare-metal behavior)
# kubectl -n ingress-nginx patch deployment ingress-nginx-controller --type=json -p='[
# {"op":"add","path":"/spec/template/spec/hostNetwork","value":true},
# {"op":"add","path":"/spec/template/spec/dnsPolicy","value":"ClusterFirstWithHostNet"}
# ]'

# kubectl rollout restart deploy ingress-nginx-controller -n ingress-nginx
########################################
# HELM
########################################
log "Installing Helm"

if ! command -v helm &>/dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# ########################################
# # ArgoCD
# ########################################
# log "Installing ArgoCD"

# kubectl create ns argocd || true

# helm repo add argo https://argoproj.github.io/argo-helm
# helm repo update

# helm upgrade --install argocd argo/argo-cd \
#   -n argocd \
#   # --set server.service.type=NodePort \
#   --set server.service.type=ClusterIP \
#   --set server.extraArgs="{--insecure}"

# kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

########################################
# Jenkins
########################################
# log "Installing Jenkins"

# apt-get install -y openjdk-17-jdk

# # remove old broken repo + keys
# sudo rm -f /etc/apt/sources.list.d/jenkins.list
# sudo rm -f /etc/apt/keyrings/jenkins*
# sudo rm -rf /var/lib/apt/lists/*

# # create keyring dir
# sudo mkdir -p /etc/apt/keyrings

# # install NEW official key (2026)
# sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
#   https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

# # add repo (official format)
# echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
#  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# # update
# sudo apt update

# sudo apt install -y fontconfig openjdk-21-jre
# sudo apt install -y jenkins
# sudo systemctl enable --now jenkins
# sudo systemctl start jenkins

# sudo mkdir -p /root/.kube
# sudo cp /etc/kubernetes/admin.conf /root/.kube/config
# sudo chown root:root /root/.kube/config

########################################
# OUTPUT
########################################
log "Installation Complete"

echo
echo "Kubernetes:"
kubectl get nodes
echo

# echo "ArgoCD URL:"
# echo "http://$IP:$NODEPORT"
# echo "Username: admin"
# kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
# echo
# echo

# echo "Jenkins URL:"
# echo "http://$IP:8080"
# echo "Password:"
# cat /var/lib/jenkins/secrets/initialAdminPassword
# echo