output "public_ip" {
  value = azurerm_public_ip.pip.ip_address
}

output "ssh_command" {
  value = "ssh ${var.admin_username}@${azurerm_public_ip.pip.fqdn}"
  # sensitive   = true
}

output "argocd_url" {
  value = "https://argocd-${replace(azurerm_public_ip.pip.ip_address, ".", "-")}.nip.io"
}

output "jenkins_url" {
  value = "https://jenkins-${replace(azurerm_public_ip.pip.ip_address, ".", "-")}.nip.io"
}

output "tekton_url" {
  value = "https://tekton-${replace(azurerm_public_ip.pip.ip_address, ".", "-")}.nip.io"
}

output "sonarqube_url" {
  value = "https://sonarqube-${replace(azurerm_public_ip.pip.ip_address, ".", "-")}.nip.io"
}

output "defectdojo_url" {
  value = "https://defectdojo-${replace(azurerm_public_ip.pip.ip_address, ".", "-")}.nip.io"
}

output "defectdojo_admin_password" {
  description = "Auto-generated admin password for DefectDojo"
  value       = random_password.defectdojo_admin.result
  sensitive   = true
}

output "argocd_admin_password" {
  description = "ArgoCD initial admin password"
  value       = local.passwords.ARGOCD_PASSWORD
  sensitive   = true
}

output "jenkins_admin_password" {
  description = "Jenkins initial admin password"
  value       = local.passwords.JENKINS_PASSWORD
  sensitive   = true
}

output "sonarqube_admin_password" {
  description = "Auto-generated admin password for SonarQube"
  value       = random_password.sonarqube_admin.result
  sensitive   = true
}

output "ROOT_DOMAIN" {
  value = "https://devsecops.switzerlandnorth.cloudapp.azure.com"
}