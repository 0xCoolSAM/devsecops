output "public_ip" {
  value = azurerm_public_ip.pip.ip_address
}

output "ssh_command" {
  value = "ssh ${var.admin_username}@${azurerm_public_ip.pip.fqdn}"
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
  description = "Admin password for DefectDojo"
  value       = "Admin@123"
  # sensitive   = true
}

output "argocd_admin_password" {
  value     = local.passwords.ARGOCD_PASSWORD
  # sensitive = true
}

output "jenkins_admin_password" {
  value     = local.passwords.JENKINS_PASSWORD
  # sensitive = true
}

output "ROOT_DOMAIN" {
  value = "https://devsecops.switzerlandnorth.cloudapp.azure.com"
}