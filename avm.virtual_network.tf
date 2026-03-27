module "virtual_network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.16.0"

  name          = local.resource_names.virtual_network_name
  location      = var.location
  address_space = [var.address_space]
  parent_id     = module.resource_group.resource_id

  subnets = {
    AzureFirewallSubnet = {
      name             = "AzureFirewallSubnet"
      address_prefixes = [var.firewall_subnet_address_prefix]
      nat_gateway = {
        id = module.nat_gateway.resource_id
      }
    }
  }

  tags = var.tags
}
