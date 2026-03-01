
variable "vm_name" {
  default = "devsecops" ## DNS
}

variable "admin_username" {
  default = "hossam"
}

variable "admin_password" {
  sensitive = true
}

variable "location" {
  default = "Switzerland North"
}