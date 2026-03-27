module "firewall_public_ip" {
  source  = "Azure/avm-res-network-publicipaddress/azurerm"
  version = "0.2.0"

  name                = local.resource_names.public_ip_name
  location            = var.location
  resource_group_name = module.resource_group.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [for z in var.availability_zones : tonumber(z)]
  # diagnostic_settings intentionally omitted from module — managed below
  # to work around a perpetual drift caused by the Azure API not returning
  # log_analytics_destination_type in GET responses for Public IP resources.
  tags = var.tags
}

# Diagnostic setting for the Firewall Public IP.
# Managed outside the AVM module so we can apply lifecycle.ignore_changes on
# log_analytics_destination_type, which permanently eliminates the perpetual
# drift caused by the Azure API omitting that field in read responses.
resource "azurerm_monitor_diagnostic_setting" "firewall_pip" {
  name                           = "send-to-law"
  target_resource_id             = module.firewall_public_ip.public_ip_id
  log_analytics_workspace_id     = module.log_analytics_workspace.resource_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }

  lifecycle {
    ignore_changes = [log_analytics_destination_type]
  }
}

# State migration: moves the existing module-managed diagnostic setting into the
# root-managed resource above without destroying and recreating it.
moved {
  from = module.firewall_public_ip.azurerm_monitor_diagnostic_setting.this["send_to_log_analytics"]
  to   = azurerm_monitor_diagnostic_setting.firewall_pip
}
