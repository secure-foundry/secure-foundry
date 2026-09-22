# vpn_router — a Tailscale subnet router on a small Azure VM. Azure
# analog of the AWS (Fargate) and GCP (Compute Engine) vpn_router
# modules. Same reasoning as the GCP module for why a persistent VM,
# not a serverless container: a subnet router needs a stable,
# VNet-resident target that external tailnet clients can route through,
# which Container Apps' own networking model doesn't provide the same
# way a persistent VM's NIC does.

terraform {
  required_providers {
    tls = { source = "hashicorp/tls" }
  }
}

variable "env_name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "app_subnet_id" { type = string }
variable "advertised_cidr" { type = string }
variable "key_vault_id" { type = string }
variable "key_vault_name" {
  type        = string
  description = "The vault's short name (not its resource ID) -- the Azure CLI's own secret-show command takes this, not the ID used for the role-assignment scope above."
}
variable "tailscale_authkey_secret_name" {
  type        = string
  description = "Key Vault secret name holding a Tailscale reusable, tagged, ephemeral auth key -- a one-time human-provided bootstrap secret."
}

resource "azurerm_user_assigned_identity" "router" {
  name                = "${var.env_name}-vpn-router"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_role_assignment" "authkey_access" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.router.principal_id
}

resource "azurerm_network_interface" "router" {
  name                = "${var.env_name}-vpn-router-nic"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.app_subnet_id
    private_ip_address_allocation = "Dynamic"
    # No public IP -- this VM is reached only via the tailnet it creates.
  }
}

# Azure requires a non-empty SSH key OR a password on every Linux VM --
# there's no "no credential at all" option at the API level. This
# generates a throwaway keypair whose PRIVATE half is never output,
# referenced, or given to any human -- it exists only to satisfy the
# API's required-field validation, achieving the same practical effect
# as "no standing SSH credential" described in the VM resource's own
# comment below, without fighting the provider to get there.
resource "tls_private_key" "router" {
  algorithm = "ED25519"
}

resource "azurerm_linux_virtual_machine" "router" {
  name                = "${var.env_name}-vpn-router"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = "Standard_B1s" # smallest general-purpose size -- this VM only relays, does no compute of its own
  admin_username      = "azureuser"

  network_interface_ids = [azurerm_network_interface.router.id]

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.router.id]
  }

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.router.public_key_openssh
  }
  # No REAL, usable SSH key configured on purpose -- the private half of
  # the keypair above is discarded (never output by this module), so
  # nothing can actually authenticate with it. This VM is administered
  # entirely via its cloud-init/custom-data bootstrap and the Tailscale
  # tailnet itself (once joined, reach it the same way you'd reach any
  # other tailnet node) -- not via a standing SSH credential, which
  # would reintroduce exactly the bastion-host-style standing access
  # this whole pattern exists to avoid. Wire in a real, human-held key
  # only if your own operational model genuinely needs direct SSH as a
  # break-glass path.

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOF
    #cloud-config
    package_update: true
    packages:
      - docker.io
    write_files:
      - path: /opt/start-tailscale.sh
        permissions: '0755'
        content: |
          #!/bin/bash
          set -euo pipefail
          az login --identity --username ${azurerm_user_assigned_identity.router.client_id} >/dev/null
          AUTHKEY=$(az keyvault secret show --vault-name "${var.key_vault_name}" --name "${var.tailscale_authkey_secret_name}" --query value -o tsv)
          docker run -d --name tailscale --restart=always \
            -e TS_AUTHKEY="$AUTHKEY" \
            -e TS_ROUTES="${var.advertised_cidr}" \
            -e TS_USERSPACE=true \
            -e TS_EXTRA_ARGS="--advertise-tags=tag:ci --accept-routes=false" \
            tailscale/tailscale:stable
    runcmd:
      - systemctl enable --now docker
      - curl -sL https://aka.ms/InstallAzureCLIDeb | bash
      - /opt/start-tailscale.sh
  EOF
  )
}
