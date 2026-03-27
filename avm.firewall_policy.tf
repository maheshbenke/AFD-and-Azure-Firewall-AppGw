module "firewall_policy" {
  source  = "Azure/avm-res-network-firewallpolicy/azurerm"
  version = "0.3.4"

  name                = local.resource_names.firewall_policy_name
  location            = var.location
  resource_group_name = module.resource_group.name
  firewall_policy_sku = var.firewall_sku_tier
  tags                = var.tags
}
