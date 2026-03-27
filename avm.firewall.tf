module "firewall" {
  source  = "Azure/avm-res-network-azurefirewall/azurerm"
  version = "0.4.0"

  name                = local.resource_names.firewall_name
  location            = var.location
  resource_group_name = module.resource_group.name

  firewall_sku_name = var.firewall_sku_name
  firewall_sku_tier = var.firewall_sku_tier
  firewall_zones    = var.availability_zones

  firewall_policy_id = module.firewall_policy.resource_id

  ip_configurations = {
    default = {
      name                 = "ipconfig1"
      subnet_id            = module.virtual_network.subnets["AzureFirewallSubnet"].resource_id
      public_ip_address_id = module.firewall_public_ip.resource_id
    }
  }

  firewall_private_ip_ranges = var.firewall_private_ip_ranges

  diagnostic_settings = local.diagnostic_settings
  tags                = var.tags
}
