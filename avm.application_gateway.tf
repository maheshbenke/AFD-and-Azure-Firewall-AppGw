module "application_gateway" {
  source  = "Azure/avm-res-network-applicationgateway/azurerm"
  version = "0.5.2"

  name                = local.resource_names.appgw_name
  location            = var.location
  resource_group_name = module.resource_group.name

  # Subnet for the Application Gateway
  gateway_ip_configuration = {
    name      = "appgw-ipconfig"
    subnet_id = module.spoke_virtual_network.subnets["appgw"].resource_id
  }

  # Frontend public IP — created internally by the module
  frontend_ip_configuration_public_name = "appgw-public-frontend"

  public_ip_address_configuration = {
    create_public_ip_enabled = true
    public_ip_name           = local.resource_names.appgw_public_ip_name
    allocation_method        = "Static"
    sku                      = "Standard"
    zones                    = var.availability_zones
  }

  # SKU — WAF_v2 for Web Application Firewall capability
  sku = {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = var.appgw_capacity
  }

  # WAF is controlled via external policy (app_gateway_waf_policy_resource_id below).
  # Inline waf_configuration is omitted — the policy takes precedence.
  app_gateway_waf_policy_resource_id = azurerm_web_application_firewall_policy.appgw_waf.id
  force_firewall_policy_association  = true

  # ---------------------------------------------------------------------------
  # Pattern 2: Private Link configuration
  # Set enable_appgw_private_link = true to activate this block.
  # Creates a Private Link service NIC in the dedicated pvtlink subnet so that
  # Front Door Premium can reach the AppGW via a managed Private Endpoint.
  # ---------------------------------------------------------------------------
  private_link_configuration = var.enable_appgw_private_link ? toset([{
    name = local.resource_names.appgw_pvtlink_config_name
    ip_configuration = [{
      name                          = "pvtlink-ipconfig"
      primary                       = true
      private_ip_address_allocation = "Dynamic"
      # try() gracefully handles the case where the pvtlink subnet doesn't yet
      # exist in state (false branch of the outer conditional is still type-checked).
      subnet_id = try(module.spoke_virtual_network.subnets["appgw-pvtlink"].resource_id, "")
    }]
  }]) : null

  # A static private IP is required to make the AVM module create the private
  # frontend IP configuration (the module only creates it when private_ip_address != null).
  # The private frontend IP lives in the AppGW subnet (var.spoke_appgw_subnet_address_prefix).
  # Front Door connects to this frontend via the Private Link service above.
  frontend_ip_configuration_private = var.enable_appgw_private_link ? {
    name                            = "appgw-private-frontend"
    private_ip_address              = var.appgw_private_frontend_ip
    private_ip_address_allocation   = "Static"
    private_link_configuration_name = local.resource_names.appgw_pvtlink_config_name
  } : {}

  # Frontend HTTP port
  frontend_ports = {
    port80 = {
      name = "port-80"
      port = 80
    }
  }

  # Backend pool — add IP addresses / FQDNs of workload VMs here
  backend_address_pools = {
    workload = {
      name = "backend-workload"
    }
  }

  # Backend HTTP settings
  backend_http_settings = {
    http80 = {
      name                  = "http-setting-80"
      port                  = 80
      protocol              = "Http"
      cookie_based_affinity = "Disabled"
      request_timeout       = 30
    }
  }

  # HTTP listener on the public frontend.
  # When enable_appgw_private_link = true, a second private listener is merged in
  # so that Front Door can probe/route through the private frontend IP.
  http_listeners = merge(
    {
      http = {
        name                           = "listener-http"
        frontend_port_name             = "port-80"
        frontend_ip_configuration_name = "appgw-public-frontend"
        protocol                       = "Http"
      }
    },
    var.enable_appgw_private_link ? {
      http-pvtlink = {
        name                           = "listener-http-pvtlink"
        frontend_port_name             = "port-80"
        frontend_ip_configuration_name = "appgw-private-frontend"
        protocol                       = "Http"
      }
    } : {}
  )

  # Basic routing rule.
  # When enable_appgw_private_link = true, a second rule for the private listener
  # is merged in — it routes Front Door's private-link traffic to the same backend pool.
  request_routing_rules = merge(
    {
      rule1 = {
        name                       = "routing-rule-1"
        rule_type                  = "Basic"
        http_listener_name         = "listener-http"
        backend_address_pool_name  = "backend-workload"
        backend_http_settings_name = "http-setting-80"
        priority                   = 100
      }
    },
    var.enable_appgw_private_link ? {
      rule-pvtlink = {
        name                       = "routing-rule-pvtlink"
        rule_type                  = "Basic"
        http_listener_name         = "listener-http-pvtlink"
        backend_address_pool_name  = "backend-workload"
        backend_http_settings_name = "http-setting-80"
        priority                   = 200
      }
    } : {}
  )

  diagnostic_settings = local.diagnostic_settings
  enable_telemetry    = true
  tags                = var.tags
}

# Application Gateway WAF policy — OWASP 3.2, Prevention mode + geo-block Russia
resource "azurerm_web_application_firewall_policy" "appgw_waf" {
  name                = local.resource_names.waf_appgw_policy_name
  location            = var.location
  resource_group_name = module.resource_group.name

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  # Custom rule — geo-block Russia (RU). Priority 1 = evaluated first.
  # Add more countries by appending ISO 3166-1 alpha-2 codes to match_values,
  # e.g. ["RU", "CN", "KP", "IR"].
  custom_rules {
    name      = "GeoBlockRussia"
    priority  = 1
    rule_type = "MatchRule"
    action    = "Block"

    match_conditions {
      operator           = "GeoMatch"
      negation_condition = false
      match_values       = ["RU"]

      match_variables {
        variable_name = "RemoteAddr"
      }
    }
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }

  tags = var.tags
}
