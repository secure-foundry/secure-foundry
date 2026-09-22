# network — resource group, VNet, NAT Gateway, and the WAF-fronted public
# entry point. Azure analog of the AWS/GCP network modules.
#
# This module owns the resource group (see accounts-azure.md for why:
# one resource group per environment, holding everything that
# environment owns) -- every other module in this environment's
# composition takes resource_group_name as an input from here, the same
# way AWS/GCP modules take a vpc_id/network_id from their own network module.

variable "env_name" { type = string }
variable "location" {
  type    = string
  default = "eastus"
}
variable "vnet_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "public_frontend" {
  type        = bool
  default     = false
  description = "true only for the one environment that should be reachable from the public internet -- see accounts-azure.md's production-only default."
}
variable "domain_name" { type = string }

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.env_name}"
  location = var.location
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.env_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = [var.vnet_cidr]
}

resource "azurerm_subnet" "app" {
  name                 = "app"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 4, 0)]

  delegation {
    name = "container-apps"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "data" {
  name                 = "data"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 4, 1)]

  delegation {
    name = "postgres-flexible-server"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-${var.env_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "this" {
  name                = "nat-${var.env_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "app" {
  subnet_id      = azurerm_subnet.app.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

resource "azurerm_network_security_group" "app" {
  name                = "nsg-app-${var.env_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  # Trust chain analog: only traffic from within the VNet (the Front
  # Door/WAF layer's private link, or the VPN router's advertised range)
  # reaches the app subnet -- mirrors the ALB-only ingress rule in the
  # AWS/GCP network modules.
  security_rule {
    name                       = "AllowVNetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_dns_zone" "public" {
  name                = var.domain_name
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone" "private" {
  name                = var.domain_name
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                = "${var.env_name}-link"
  private_dns_zone_id = azurerm_private_dns_zone.private.id
  virtual_network_id  = azurerm_virtual_network.this.id
}

resource "azurerm_web_application_firewall_policy" "this" {
  name                = "waf-${var.env_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  managed_rules {
    managed_rule_set {
      type    = "Microsoft_DefaultRuleSet"
      version = "2.1"
    }
  }

  custom_rules {
    name      = "RateLimitPerIP"
    priority  = 1
    rule_type = "RateLimitRule"
    action    = "Block"

    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }
      operator     = "IPMatch"
      match_values = ["0.0.0.0/0"]
    }

    rate_limit_duration  = "OneMin"
    rate_limit_threshold = 2000
  }

  policy_settings {
    enabled = true
    mode    = "Prevention"
  }
}

output "resource_group_name" { value = azurerm_resource_group.this.name }
output "location" { value = azurerm_resource_group.this.location }
output "vnet_id" { value = azurerm_virtual_network.this.id }
output "app_subnet_id" { value = azurerm_subnet.app.id }
output "data_subnet_id" { value = azurerm_subnet.data.id }
output "waf_policy_id" { value = azurerm_web_application_firewall_policy.this.id }
output "private_dns_zone_id" { value = azurerm_private_dns_zone.private.id }
output "public_dns_zone_name_servers" { value = azurerm_dns_zone.public.name_servers }
