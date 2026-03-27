resource "azurerm_route_table" "spoke" {
  name                          = local.resource_names.spoke_route_table_name
  location                      = var.location
  resource_group_name           = module.resource_group.name
  bgp_route_propagation_enabled = false

  tags = var.tags
}

resource "azurerm_route" "spoke_default" {
  name                   = "route-to-firewall"
  resource_group_name    = module.resource_group.name
  route_table_name       = azurerm_route_table.spoke.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = module.firewall.resource.ip_configuration[0].private_ip_address
}
