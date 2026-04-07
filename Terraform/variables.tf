
variable "vm_name" {
  description = "Name of the VM and DNS label"
  default     = "devsecops" ## DNS
}

variable "admin_username" {
  description = "SSH admin username for the VM"
  default     = "hossam"
}

variable "admin_password" {
  description = "SSH admin password for the VM"
  sensitive   = true
}

variable "location" {
  description = "Azure region for all resources"
  default     = "Switzerland North"
}

variable "allowed_ip_cidr" {
  description = "CIDR block allowed to access the VM (e.g. your IP/32). Use '*' only for development."
  type        = string
  default     = "*"

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.allowed_ip_cidr)) || var.allowed_ip_cidr == "*"
    error_message = "allowed_ip_cidr must be a valid CIDR block (e.g. 203.0.113.0/32) or '*' for open access."
  }
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for pipeline notifications. Leave empty to disable."
  type        = string
  default     = ""
  sensitive   = true
}

variable "git_token" {
  description = "GitHub Personal Access Token for Tekton GitOps push. Leave empty to configure manually."
  type        = string
  default     = ""
  sensitive   = true
}

variable "git_username" {
  description = "GitHub username for GitOps repository authentication."
  type        = string
  default     = "0x70ssAM"
}

variable "dockerhub_username" {
  description = "DockerHub username for image push."
  type        = string
  default     = "hossamibraheem"
}

variable "dockerhub_token" {
  description = "DockerHub Personal Access Token."
  type        = string
  default     = ""
  sensitive   = true
}

variable "dockerhub_repository" {
  description = "DockerHub repository (e.g., username/devsecops)."
  type        = string
  default     = "hossamibraheem/devsecops"
}
