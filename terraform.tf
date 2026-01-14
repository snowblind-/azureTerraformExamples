terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Variables
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "bigip-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "East US"
}

variable "vnet_name" {
  description = "Virtual network name"
  type        = string
  default     = "bigip-vnet"
}

variable "vnet_address_space" {
  description = "Virtual network address space"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "mgmt_subnet_name" {
  description = "Management subnet name"
  type        = string
  default     = "mgmt-subnet"
}

variable "mgmt_subnet_prefix" {
  description = "Management subnet prefix"
  type        = string
  default     = "10.0.1.0/24"
}

variable "external_subnet_name" {
  description = "External subnet name"
  type        = string
  default     = "external-subnet"
}

variable "external_subnet_prefix" {
  description = "External subnet prefix"
  type        = string
  default     = "10.0.2.0/24"
}

variable "custom_image_id" {
  description = "Resource ID of the custom BIG-IP image"
  type        = string
}

variable "instance_type" {
  description = "Azure VM size"
  type        = string
}

variable "admin_username" {
  description = "Admin username for BIG-IP"
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "Admin password for BIG-IP"
  type        = string
  sensitive   = true
}

variable "use_ssh_key" {
  description = "Use SSH key authentication instead of password"
  type        = bool
  default     = false
}

variable "ssh_public_key" {
  description = "SSH public key for authentication"
  type        = string
  default     = ""
}

# Resource Group
resource "azurerm_resource_group" "bigip" {
  name     = var.resource_group_name
  location = var.location
}

# Virtual Network
resource "azurerm_virtual_network" "bigip" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.bigip.location
  resource_group_name = azurerm_resource_group.bigip.name
}

# Management Subnet
resource "azurerm_subnet" "mgmt" {
  name                 = var.mgmt_subnet_name
  resource_group_name  = azurerm_resource_group.bigip.name
  virtual_network_name = azurerm_virtual_network.bigip.name
  address_prefixes     = [var.mgmt_subnet_prefix]
}

# External Subnet
resource "azurerm_subnet" "external" {
  name                 = var.external_subnet_name
  resource_group_name  = azurerm_resource_group.bigip.name
  virtual_network_name = azurerm_virtual_network.bigip.name
  address_prefixes     = [var.external_subnet_prefix]
}

# Network Security Group for Management
resource "azurerm_network_security_group" "mgmt" {
  name                = "bigip-mgmt-nsg"
  location            = azurerm_resource_group.bigip.location
  resource_group_name = azurerm_resource_group.bigip.name

  security_rule {
    name                       = "allow-https"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-ssh"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Network Security Group for External
resource "azurerm_network_security_group" "external" {
  name                = "bigip-external-nsg"
  location            = azurerm_resource_group.bigip.location
  resource_group_name = azurerm_resource_group.bigip.name

  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Public IP for Management Interface
resource "azurerm_public_ip" "mgmt" {
  name                = "bigip-mgmt-pip"
  location            = azurerm_resource_group.bigip.location
  resource_group_name = azurerm_resource_group.bigip.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Public IP for External Interface
resource "azurerm_public_ip" "external" {
  name                = "bigip-external-pip"
  location            = azurerm_resource_group.bigip.location
  resource_group_name = azurerm_resource_group.bigip.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Management Network Interface
resource "azurerm_network_interface" "mgmt" {
  name                = "bigip-mgmt-nic"
  location            = azurerm_resource_group.bigip.location
  resource_group_name = azurerm_resource_group.bigip.name

  ip_configuration {
    name                          = "mgmt-ipconfig"
    subnet_id                     = azurerm_subnet.mgmt.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.mgmt.id
  }
}

# External Network Interface
resource "azurerm_network_interface" "external" {
  name                = "bigip-external-nic"
  location            = azurerm_resource_group.bigip.location
  resource_group_name = azurerm_resource_group.bigip.name

  ip_configuration {
    name                          = "external-ipconfig"
    subnet_id                     = azurerm_subnet.external.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.external.id
  }
}

# Associate NSG with Management NIC
resource "azurerm_network_interface_security_group_association" "mgmt" {
  network_interface_id      = azurerm_network_interface.mgmt.id
  network_security_group_id = azurerm_network_security_group.mgmt.id
}

# Associate NSG with External NIC
resource "azurerm_network_interface_security_group_association" "external" {
  network_interface_id      = azurerm_network_interface.external.id
  network_security_group_id = azurerm_network_security_group.external.id
}

# F5 BIG-IP Virtual Machine using Custom Image
resource "azurerm_linux_virtual_machine" "bigip" {
  name                = "bigip-vm"
  location            = azurerm_resource_group.bigip.location
  resource_group_name = azurerm_resource_group.bigip.name
  size                = var.instance_type
  admin_username      = var.admin_username
  
  # Use either password or SSH key authentication
  disable_password_authentication = var.use_ssh_key
  
  # Password authentication (used when use_ssh_key = false)
  admin_password = var.use_ssh_key ? null : var.admin_password

  # SSH key authentication (used when use_ssh_key = true)
  dynamic "admin_ssh_key" {
    for_each = var.use_ssh_key ? [1] : []
    content {
      username   = var.admin_username
      public_key = var.ssh_public_key
    }
  }

  network_interface_ids = [
    azurerm_network_interface.mgmt.id,
    azurerm_network_interface.external.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  # Use custom image instead of marketplace image
  source_image_id = var.custom_image_id
}

# Outputs
output "bigip_mgmt_public_ip" {
  description = "Management public IP address"
  value       = azurerm_public_ip.mgmt.ip_address
}

output "bigip_external_public_ip" {
  description = "External public IP address"
  value       = azurerm_public_ip.external.ip_address
}

output "bigip_mgmt_url" {
  description = "BIG-IP management URL"
  value       = "https://${azurerm_public_ip.mgmt.ip_address}"
}

output "bigip_vm_id" {
  description = "BIG-IP VM resource ID"
  value       = azurerm_linux_virtual_machine.bigip.id
}
