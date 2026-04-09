# Cloud Native DevSecOps Platform

## Overview

This project provisions a comprehensive, automated DevSecOps platform utilizing modern Infrastructure-as-Code and GitOps principles. The integration leverages:
- **Terraform** for base infrastructure provisioning
- **Ansible** for declarative configuration and clustering logic
- **Kubernetes** as the core container orchestration engine
- **Tekton Pipelines** for cloud-native CI automation
- **ArgoCD** for continuous deployment and GitOps sync
- **DefectDojo** for automated security vulnerability aggregation and tracking
- **SonarQube** for Static Application Security Testing (SAST)
- **Jenkins** for peripheral build tasks and legacy system interoperability
- **Docker** for containerization environments
- **Nginx Ingress + TLS (Cert-Manager)** for secure platform web exposure

### The Workflow
1. **Infrastructure**: Terraform intelligently provisions the target Azure VM and tracks networking state.
2. **Configuration**: Ansible hooks directly into the provisioned VM, bootstraps the Docker/Containerd runtime, initializes `kubeadm`, configures storage modules, and establishes Nginx ingress routing.
3. **Platform Tooling**: Crucial DevSecOps modules (DefectDojo, Tekton, ArgoCD, SonarQube) are continuously declared and deployed via Helm charts embedded into the Ansible execution flow.
4. **CI Security Parsing**: Code changes pass through Tekton, dynamically triggering deeply nested security layers.
5. **Vulnerability Rollup**: All scanning results correctly coalesce directly into the DefectDojo reporting logic.
6. **GitOps Rollout**: Successfully signed and thoroughly evaluated artifacts are pulled by ArgoCD using strict declarative source-of-truth syncing strategies.

---

## Architecture

```text
Developer Push 
  → Tekton Pipeline 
    → Security Scans (SAST, SCA, Image scanning) 
      → Kaniko Image Build 
        → Docker Registry Push
          → Image Chain Verification (Cosign)
            → ArgoCD Validation 
              → Kubernetes Deployment 
                → DefectDojo Aggregation Results
```

---

## Features
- **Infrastructure as Code (IaC)** securely managed entirely via Terraform.
- **Configuration Management**: Fully automated bootstrapping via strict Ansible roles tracking configuration state.
- **End-to-End Pipeline Automation**: Using Tekton's unprivileged native Pod routing paradigms.
- **SAST**: Central code evaluation tracking.
- **SCA**: Dependencies dynamically analyzed for zero-day CVE matches.
- **Container Scanning**: Full layer-by-layer security validation logic attached specifically to image stages.
- **DAST**: OWASP ZAP automatically triggers upon staging exposure validation.
- **SBOM Generation**: Full Software Bill of Materials embedded per release candidate structure.
- **Supply Chain Cryptography**: Secure artifact signing via standard Sigstore/Cosign.
- **GitOps Methodology**: Declarative Git repository behavior replacing active imperative CD commands.

---

## Prerequisites

The project strictly supports running atop **WSL (Ubuntu)** to ensure compatibility with bash environments, Ansible hooks, and formatting tools. 

### Required Tools
Ensure you have the following installed locally:
- Terraform
- Ansible
- Azure CLI
- `kubectl`
- `helm`
- `jq`
- `sshpass`
- `docker`
- `git`

#### Example Installation (Ubuntu WSL)
```bash
sudo apt update && sudo apt install -y python3-pip jq git curl unzip sshpass
pip3 install ansible

# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

---

## Setup Instructions

1. **Clone repository**
```bash
git clone https://github.com/0x70ssAM/devsecops
cd devsecops
```

2. **Login to Azure**
```bash
az login
```

3. **Initialize Terraform**
```bash
cd Terraform
terraform init
```

4. **Apply infrastructure**
```bash
terraform apply
```

5. **Destroy infrastructure**
```bash
terraform destroy
```

---

## DevSecOps Pipeline

The fundamental Tekton pipeline handles immutable execution logic natively on the cluster:
- **Git Clone**: Resolves targeted target repository hashes (commits).
- **Build**: Extracts application structure and establishes the dynamic container digest.
- **Unit Tests**: Syntactic and framework code executions.
- **SAST**: Static checks verifying application source stability.
- **SCA**: Maps software dependencies dynamically.
- **Container Scan**: Discovers and mitigates active OS and container vulnerabilities.
- **SBOM Generation**: Automatically binds full visibility tracking.
- **Image signing**: Sigstore signs compiled containers explicitly against validation structures.
- **Push to registry**: The secure Docker Hub push interaction.
- **ArgoCD deployment**: Manifest deployment triggers the declarative `argocd` system.
- **DefectDojo reporting**: Pushes generated scan assets (Trivy, Grype, Syft) directly into the Dojo ecosystem.

---

## Security Tools Used
- **SonarQube**: Static code quality and security gate enforcement.
- **Trivy**: Comprehensive container layout vulnerability resolution.
- **Syft**: Unrivaled SBOM composition builder tracking.
- **Grype**: Vulnerability detection engine against embedded SBOM layers.
- **OWASP ZAP**: Dynamic attack path verification.
- **Cosign**: Supply chain cryptographical verification toolkit.
- **DefectDojo**: Consolidated, multi-faceted vulnerability tracker and analytics UI.

---

## Repository Structure
```text
Terraform/     # IaC code mapping virtual machines, routing, and access.
Ansible/       # Reusable configuration roles isolating component installs.
Tekton/        # CI deployment modules dictating steps and logic handlers.
k8s/           # Base deployment templates handling runtime states natively.
scripts/       # Auxiliary runtime behavior scripts.
```

---

## Future Improvements
- **Secrets Management**: Refactor raw secret creation into an integrated HashiCorp Vault native environment.
- **GitHub Actions Integration**: Trigger deployment loops dynamically without needing local workstation invocation.
- **OPA Policy Enforcement**: Deploy the Open Policy Agent to proactively block non-compliant Kubernetes pods statically across the cluster layer.
- **Admission Controller Security**: Validate artifact sigstore logic strictly at the kubernetes ingress validation stage.
- **Cluster Runtime Security**: Establish eBPF capabilities like Falco tracking malicious active cluster threads safely.