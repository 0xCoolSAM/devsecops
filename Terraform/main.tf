terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

############################################
# Resource Group
############################################
resource "azurerm_resource_group" "rg" {
  name     = "devsecops-rg"
  location = var.location
}

############################################
# Public IP
############################################
resource "azurerm_public_ip" "pip" {
  name                = "devsecops-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  domain_name_label = var.vm_name ## DNS
}

############################################
# NSG
############################################
resource "azurerm_network_security_group" "nsg" {
  name                = "devsecops-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

locals {
  inbound_ports = [
    "22",
    "80",
    "443",
    "8080"
  ]
}

resource "azurerm_network_security_rule" "inbound_rules" {
  for_each = {
    for idx, port in local.inbound_ports :
    port => idx
  }

  name                        = "port-${each.key}"
  priority                    = 100 + each.value
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.key
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

# NodePort range
resource "azurerm_network_security_rule" "nodeports" {
  name                        = "nodeports"
  priority                    = 500
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "30000-32767"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

############################################
# VNet
############################################
resource "azurerm_virtual_network" "vnet" {
  name                = "devsecops-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

############################################
# NIC
############################################
resource "azurerm_network_interface" "nic" {
  name                = "devsecops-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    public_ip_address_id          = azurerm_public_ip.pip.id
    private_ip_address_allocation = "Dynamic"
  }
}

############################################
# Associate NSG
############################################
resource "azurerm_subnet_network_security_group_association" "assoc" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

############################################
# VM
############################################
resource "azurerm_linux_virtual_machine" "vm" {
  name                = var.vm_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = "Standard_E4ds_v4"

  admin_username = var.admin_username
  admin_password = var.admin_password

  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # custom_data = base64encode(file("bootstrap.sh"))

  # provisioner "file" {
  #   source      = "bootstrap.sh"
  #   destination = "/home/${var.admin_username}/bootstrap.sh"

  #   connection {
  #     type     = "ssh"
  #     user     = var.admin_username
  #     password = var.admin_password
  #     host     = azurerm_public_ip.pip.ip_address
  #   }
  # }

  # provisioner "remote-exec" {
  #   inline = [
  #     "chmod +x bootstrap.sh",
  #     "sudo ./bootstrap.sh"
  #   ]

  #   connection {
  #     type     = "ssh"
  #     user     = var.admin_username
  #     password = var.admin_password
  #     host     = azurerm_public_ip.pip.ip_address
  #   }
  # }

}

resource "null_resource" "bootstrap" {

  depends_on = [azurerm_linux_virtual_machine.vm]

  connection {
    type     = "ssh"
    host     = azurerm_public_ip.pip.ip_address
    user     = var.admin_username
    password = var.admin_password
    timeout  = "5m"
  }

  provisioner "file" {
    source      = "bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/bootstrap.sh",
      "sudo bash /tmp/bootstrap.sh"
    ]
  }
}

resource "null_resource" "fetch_passwords" {
  depends_on = [null_resource.bootstrap]

  provisioner "local-exec" {
    command = "sshpass -p '${var.admin_password}' scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${var.admin_username}@${azurerm_public_ip.pip.ip_address}:/etc/devsecops/passwords.json ./passwords.json"
  }
}

data "local_file" "platform_passwords" {
  depends_on = [null_resource.fetch_passwords]
  filename   = "${path.module}/passwords.json"
}

locals {
  passwords = jsondecode(data.local_file.platform_passwords.content)
}

# data "external" "platform_passwords" {
#   depends_on = [null_resource.bootstrap]

#   program = [
#     "bash",
#     "-c",
#     <<EOT
# sshpass -p '${var.admin_password}' ssh -o StrictHostKeyChecking=no ${var.admin_username}@${azurerm_public_ip.pip.ip_address} \
# "cat /tmp/passwords.env" | awk -F= '
# {
#   gsub("\r","")
#   printf "\"%s\":\"%s\",", $1, $2
# }
# END {
#   print ""
# }' | sed 's/,$//' | awk '{print "{" $0 "}"}'
# EOT
#   ]
# }

# data "external" "argocd_admin_password" {
#   depends_on = [null_resource.bootstrap]

#   program = [
#     "bash",
#     "-c",
#     "sshpass -p '${var.admin_password}' ssh -o StrictHostKeyChecking=no ${var.admin_username}@${azurerm_public_ip.pip.ip_address} \"kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d\" | jq -Rn '{password: input}'"
#   ]
# }

# data "external" "jenkins_admin_password" {
#   depends_on = [null_resource.bootstrap]

#   program = [
#     "bash",
#     "-c",
#     "sshpass -p '${var.admin_password}' ssh -o StrictHostKeyChecking=no ${var.admin_username}@${azurerm_public_ip.pip.ip_address} \"sudo cat /var/lib/jenkins/secrets/initialAdminPassword\" | jq -Rn '{password: input}'"
#   ]
# }

# resource "azurerm_virtual_machine_extension" "bootstrap" {
#   name                 = "bootstrap"
#   virtual_machine_id   = azurerm_linux_virtual_machine.vm.id
#   publisher            = "Microsoft.Azure.Extensions"
#   type                 = "CustomScript"
#   type_handler_version = "2.1"

#   protected_settings = jsonencode({
#     commandToExecute = "bash -c \"cat > /tmp/bootstrap.sh << 'EOF'\n${file("bootstrap.sh")}\nEOF\nchmod +x /tmp/bootstrap.sh\nbash /tmp/bootstrap.sh\""
#   })
# }