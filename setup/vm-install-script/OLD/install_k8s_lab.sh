#!/bin/bash
set -e

echo "========= SYSTEM PREP ========="

# Nice prompt
echo "force_color_prompt=yes" >> ~/.bashrc

# Disable restart prompts
[ -f /etc/needrestart/needrestart.conf ] && \
sed -i "s/#\$nrconf{restart} = 'i'/\$nrconf{restart} = 'a'/" /etc/needrestart/needrestart.conf

apt-get update -y
apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release software-properties-common

# Required kernel modules
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Required sysctl params
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# Disable swap (Kubernetes requirement)
swapoff -a
sed -i '/swap/d' /etc/fstab

echo "========= CONTAINERD ========="

apt-get install -y containerd

mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' \
    | tee /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

echo "========= KUBERNETES INSTALL ========="

KUBE_LATEST=$(curl -L -s https://dl.k8s.io/release/stable.txt | cut -d. -f1,2)

mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBE_LATEST}/deb/Release.key \
 | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/${KUBE_LATEST}/deb/ /" \
 | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

echo "========= CLUSTER INIT ========="

kubeadm reset -f || true

kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --service-cidr=10.96.0.0/16 \
  --skip-token-print

mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

echo "========= NETWORK (FLANNEL) ========="

kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

echo "Waiting for network..."
sleep 20

echo "========= UNTAINT CONTROL PLANE ========="

NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl taint node $NODE node-role.kubernetes.io/control-plane- || true

kubectl get nodes -o wide

echo "========= JAVA + MAVEN ========="

apt-get install -y openjdk-17-jdk maven
java -version
mvn -v

echo "========= JENKINS ========="

curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
 | tee /usr/share/keyrings/jenkins.gpg > /dev/null

echo deb [signed-by=/usr/share/keyrings/jenkins.gpg] \
http://pkg.jenkins.io/debian-stable binary/ \
 | tee /etc/apt/sources.list.d/jenkins.list > /dev/null

apt-get update -y
apt-get install -y jenkins

systemctl enable jenkins
systemctl start jenkins

usermod -aG docker jenkins || true
echo "jenkins ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

echo "========= INSTALL HELM ========="

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

echo "========= ADD ARGOCD HELM REPO ========="

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "========= CREATE NAMESPACE ========="

kubectl create namespace argocd || true

echo "========= INSTALL ARGOCD ========="

helm install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=NodePort \
  --set server.extraArgs="{--insecure}"

echo "Waiting for ArgoCD pods..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

echo "========= GET NODEPORT ========="

NODEPORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[0].nodePort}')
IP=$(hostname -I | awk '{print $1}')

echo
echo "========================================="
echo
echo "========= INSTALL COMPLETE ========="
echo
kubectl get nodes
echo
echo "Jenkins initial password:"
cat /var/lib/jenkins/secrets/initialAdminPassword
echo "========= ARGOCD ADMIN PASSWORD ========="

kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo
echo "USERNAME: admin"
