module "nat_gateway" {
  source  = "Azure/avm-res-network-natgateway/azurerm"
  version = "0.3.2"

  name      = local.resource_names.nat_gateway_name
  location  = var.location
  parent_id = module.resource_group.resource_id

  public_ips = {
    pip_1 = {
      name = local.resource_names.nat_gateway_public_ip_name
    }
  }

  tags = var.tags
}
