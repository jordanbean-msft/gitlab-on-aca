########## Network Module (attaches NSGs to existing subnets) ##########

# Assumes VNet and subnets already exist; we only create NSGs and associate.

resource "azurerm_network_security_group" "container_apps" {
  name                = "nsg-ca-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowCAEControlPlane"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureCloud"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowInternalComms"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Allow outbound NFS (2049) and SMB (445) traffic from Container Apps subnet to Azure Files private endpoint subnet
  security_rule {
    name                       = "AllowOutboundFileShareNFS"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["2049", "445"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Required for Azure Files NFS (2049) and SMB (445) mounts from container apps to private endpoint"
  }
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-pe-${var.unique_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowPrivateEndpointInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

# Subnet associations (no creation of subnets)
resource "azurerm_subnet_network_security_group_association" "container_apps" {
  subnet_id                 = var.container_apps_subnet_id
  network_security_group_id = azurerm_network_security_group.container_apps.id
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = var.private_endpoints_subnet_id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}
