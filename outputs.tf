output "resource_names" {
  description = "The computed resource names."
  value       = local.resource_names
}

output "resource_ids" {
  description = "The resource IDs of all deployed resources."
  value = {
    resource_group          = module.resource_group.resource_id
    log_analytics_workspace = module.log_analytics_workspace.resource_id
    virtual_network         = module.virtual_network.resource_id
    firewall_subnet         = module.virtual_network.subnets["AzureFirewallSubnet"].resource_id
    firewall_public_ip      = module.firewall_public_ip.resource_id
    firewall_policy         = module.firewall_policy.resource_id
    firewall                = module.firewall.resource_id
    nat_gateway             = module.nat_gateway.resource_id
    network_rule_group      = azurerm_firewall_policy_rule_collection_group.network.id
    application_rule_group  = azurerm_firewall_policy_rule_collection_group.application.id
    spoke_virtual_network   = module.spoke_virtual_network.resource_id
    spoke_workload_subnet   = module.spoke_virtual_network.subnets["workload"].resource_id
    spoke_appgw_subnet      = module.spoke_virtual_network.subnets["appgw"].resource_id
    spoke_route_table       = azurerm_route_table.spoke.id
    application_gateway     = module.application_gateway.resource_id
    front_door              = module.front_door.resource_id
  }
}

output "firewall_private_ip" {
  description = "The private IP address of the Azure Firewall."
  value       = module.firewall.resource.ip_configuration[0].private_ip_address
}
