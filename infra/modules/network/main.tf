########## Network Module (attaches NSGs to existing subnets) ##########

# Assumes VNet and subnets already exist; we only create NSGs and associate.

# Data source to get VNet ID from subnet ID
data "azurerm_subnet" "container_apps" {
  name                 = split("/", var.container_apps_subnet_id)[10]
  virtual_network_name = split("/", var.container_apps_subnet_id)[8]
  resource_group_name  = var.resource_group_name
}

# Virtual network data source (needed for vNet ID output)
data "azurerm_virtual_network" "vnet" {
  name                = data.azurerm_subnet.container_apps.virtual_network_name
  resource_group_name = var.resource_group_name
}

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

  # Allow outbound PostgreSQL traffic from Container Apps to PostgreSQL subnet
  security_rule {
    name                       = "AllowOutboundPostgreSQL"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Required for PostgreSQL database connectivity"
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

  # Allow inbound NFS (2049) and SMB (445) traffic to private endpoints subnet for Azure Files
  security_rule {
    name                       = "AllowInboundFileShareNFS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["2049", "445"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
    description                = "Required for Azure Files NFS (2049) and SMB (445) access via private endpoint"
  }

  # Allow inbound PostgreSQL traffic to private endpoints subnet
  security_rule {
    name                       = "AllowInboundPostgreSQL"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
    description                = "Required for PostgreSQL database access via private endpoint"
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
