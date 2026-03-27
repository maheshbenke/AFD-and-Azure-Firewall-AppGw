module "spoke_virtual_network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.16.0"

  name          = local.resource_names.spoke_virtual_network_name
  location      = var.location
  address_space = [var.spoke_address_space]
  parent_id     = module.resource_group.resource_id

  subnets = merge(
    {
      workload = {
        name             = "snet-workload"
        address_prefixes = [var.spoke_workload_subnet_address_prefix]
        route_table = {
          id = azurerm_route_table.spoke.id
        }
      }
      appgw = {
        name             = "snet-appgw"
        address_prefixes = [var.spoke_appgw_subnet_address_prefix]
        # No route table — AppGW v2 management traffic (ports 65200-65535)
        # must not be routed through a virtual appliance.
      }
    },
    # Pattern 2 (Private Link): dedicated /29 subnet for the AppGW Private Link
    # service NIC. private_link_service_network_policies_enabled = false is
    # REQUIRED on any subnet that hosts a Private Link *service provider*.
    var.enable_appgw_private_link ? {
      appgw-pvtlink = {
        name                                          = "snet-pvtlink-appgw"
        address_prefixes                              = [var.appgw_private_link_subnet_prefix]
        private_link_service_network_policies_enabled = false
      }
    } : {}
  )

  peerings = {
    spoke-to-hub = {
      name                                 = "peer-spoke-to-hub"
      remote_virtual_network_resource_id   = module.virtual_network.resource_id
      allow_forwarded_traffic              = true
      allow_virtual_network_access         = true
      allow_gateway_transit                = false
      use_remote_gateways                  = false
      create_reverse_peering               = true
      reverse_name                         = "peer-hub-to-spoke"
      reverse_allow_forwarded_traffic      = true
      reverse_allow_gateway_transit        = true
      reverse_allow_virtual_network_access = true
      reverse_use_remote_gateways          = false
    }
  }

  tags = var.tags
}
