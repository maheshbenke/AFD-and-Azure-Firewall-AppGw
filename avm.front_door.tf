# Data source to resolve the Application Gateway's public IP address.
# depends_on ensures Terraform reads this AFTER the AppGW (and its PIP) is created.
data "azurerm_public_ip" "appgw" {
  name                = local.resource_names.appgw_public_ip_name
  resource_group_name = module.resource_group.name
  depends_on          = [module.application_gateway]
}

module "front_door" {
  source  = "Azure/avm-res-cdn-profile/azurerm"
  version = "0.1.9"

  name                = local.resource_names.front_door_name
  location            = var.location
  resource_group_name = module.resource_group.name
  sku                 = "Premium_AzureFrontDoor"

  front_door_endpoints = {
    ep1 = {
      name    = "ep-${local.resource_names.front_door_name}"
      enabled = true
    }
  }

  front_door_origin_groups = {
    appgw = {
      name = "og-appgw"
      load_balancing = {
        lb1 = {
          additional_latency_in_milliseconds = 50
          sample_size                        = 4
          successful_samples_required        = 3
        }
      }
      health_probe = {
        hp1 = {
          interval_in_seconds = 100
          path                = "/"
          protocol            = "Http"
          request_type        = "HEAD"
        }
      }
    }
  }

  # Origin points to the Application Gateway.
  # Pattern 1 (default): public IP, no private link.
  # Pattern 2 (enable_appgw_private_link = true): this block is empty {}; the
  # private-link origin below (azurerm_cdn_frontdoor_origin.appgw_private) takes over.
  front_door_origins = var.enable_appgw_private_link ? {} : {
    appgw = {
      name                           = "origin-appgw"
      origin_group_key               = "appgw"
      host_name                      = data.azurerm_public_ip.appgw.ip_address
      certificate_name_check_enabled = false
      enabled                        = true
      http_port                      = 80
      https_port                     = 443
      priority                       = 1
      weight                         = 1000
    }
  }

  # Route: Pattern 1 only. When enable_appgw_private_link = true this is empty
  # and the raw azurerm_cdn_frontdoor_route.private_link resource below takes over.
  front_door_routes = var.enable_appgw_private_link ? {} : {
    default = {
      name                   = "route-default"
      endpoint_key           = "ep1"
      origin_group_key       = "appgw"
      origin_keys            = ["appgw"]
      supported_protocols    = ["Http", "Https"]
      patterns_to_match      = ["/*"]
      https_redirect_enabled = false
      forwarding_protocol    = "HttpOnly"
      link_to_default_domain = true
    }
  }

  enable_telemetry = true
  tags             = var.tags
}

# WAF policy — Premium DRS 2.0 + Bot Manager 1.0, Prevention mode
# Note: azurerm_cdn_frontdoor_firewall_policy name must be alphanumeric only (no hyphens).
resource "azurerm_cdn_frontdoor_firewall_policy" "waf" {
  name                              = replace(local.resource_names.waf_front_door_policy_name, "-", "")
  resource_group_name               = module.resource_group.name
  sku_name                          = "Premium_AzureFrontDoor"
  enabled                           = true
  mode                              = "Prevention"
  custom_block_response_status_code = 403

  managed_rule {
    type    = "DefaultRuleSet"
    version = "1.0"
    action  = "Block"
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }

  # Custom rule — geo-block Russia (RU). Evaluated before managed rules (priority 100).
  # To add more countries, append additional values to the match_values list
  # using ISO 3166-1 alpha-2 codes, e.g. "CN", "KP", "IR".
  custom_rule {
    name                           = "GeoBlockRussia"
    enabled                        = true
    priority                       = 100
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 0
    type                           = "MatchRule"
    action                         = "Block"

    match_condition {
      match_variable     = "SocketAddr"
      operator           = "GeoMatch"
      negation_condition = false
      match_values       = ["RU"]
    }
  }

  tags = var.tags
}

# Resolve the AFD endpoint ID created by the module (needed for security policy association)
data "azurerm_cdn_frontdoor_endpoint" "ep1" {
  name                = "ep-${local.resource_names.front_door_name}"
  profile_name        = local.resource_names.front_door_name
  resource_group_name = module.resource_group.name
  depends_on          = [module.front_door]
}

# Security policy — binds the WAF policy to the AFD endpoint
resource "azurerm_cdn_frontdoor_security_policy" "waf" {
  name                     = "secpol-waf-${local.resource_names.front_door_name}"
  cdn_frontdoor_profile_id = module.front_door.resource_id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.waf.id

      association {
        patterns_to_match = ["/*"]

        domain {
          cdn_frontdoor_domain_id = data.azurerm_cdn_frontdoor_endpoint.ep1.id
        }
      }
    }
  }
}

# =============================================================================
# Pattern 2: Front Door Premium → Private AppGW via Private Link
# Active when: var.enable_appgw_private_link = true
# =============================================================================
#
# Why azapi_resource instead of azurerm_cdn_frontdoor_origin?
# The azurerm provider sends target_type = "Gateway" as the groupId in the AFD
# REST API, but Application Gateway's private link resource exposes
# groupId = "appgw-private-frontend" (the frontend IP configuration name).
# AFD's control plane forwards exactly this groupId when creating the managed
# Private Endpoint, and AppGW rejects "Gateway" with:
#   "Cannot perform private link operation on ApplicationGateway"
# Using azapi_resource lets us set groupId = "appgw-private-frontend" directly,
# which matches what `az network private-link-resource list` returns for our AppGW.
#
# The private endpoint connection is auto-approved by the terraform_data block
# at the bottom of this file (requires Azure CLI in the same subscription context).

# Private Link origin — Front Door creates a managed Private Endpoint targeting
# the AppGW private frontend IP configuration (appgw-private-frontend).
resource "azapi_resource" "appgw_private_origin" {
  count = var.enable_appgw_private_link ? 1 : 0

  type      = "Microsoft.Cdn/profiles/originGroups/origins@2024-02-01"
  name      = "origin-appgw"
  parent_id = module.front_door.frontdoor_origin_groups["appgw"].id

  body = {
    properties = {
      hostName                    = data.azurerm_public_ip.appgw.ip_address
      httpPort                    = 80
      httpsPort                   = 443
      enabledState                = "Enabled"
      enforceCertificateNameCheck = true
      priority                    = 1
      weight                      = 1000
      sharedPrivateLinkResource = {
        privateLink = {
          id = module.application_gateway.resource_id
        }
        groupId             = "appgw-private-frontend"
        privateLinkLocation = var.location
        requestMessage      = "Front Door Private Link access for Application Gateway"
      }
    }
  }

  depends_on = [module.front_door, module.application_gateway]
}

# Route for the private-link origin. Mirrors the module-managed route (Pattern 1)
# but references the azapi origin above instead of a module-managed one.
resource "azurerm_cdn_frontdoor_route" "private_link" {
  count = var.enable_appgw_private_link ? 1 : 0

  name                          = "route-default"
  cdn_frontdoor_endpoint_id     = data.azurerm_cdn_frontdoor_endpoint.ep1.id
  cdn_frontdoor_origin_group_id = module.front_door.frontdoor_origin_groups["appgw"].id
  cdn_frontdoor_origin_ids      = [azapi_resource.appgw_private_origin[0].id]
  supported_protocols           = ["Http", "Https"]
  patterns_to_match             = ["/*"]
  https_redirect_enabled        = false
  forwarding_protocol           = "HttpOnly"
  link_to_default_domain        = true
  enabled                       = true

  depends_on = [azapi_resource.appgw_private_origin]
}

# Auto-approve the Front Door managed Private Endpoint on the AppGW side.
# Runs immediately after the AFD origin is created. Polls every 20 s (up to
# 5 minutes) for the pending connection, then approves it via Azure CLI.
# Requires: Azure CLI authenticated with permission to write to the AppGW
# (Contributor or Network Contributor on the resource group).
resource "terraform_data" "approve_afd_pvtlink" {
  count = var.enable_appgw_private_link ? 1 : 0

  # Re-trigger if the origin resource is replaced.
  input = azapi_resource.appgw_private_origin[0].id

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command     = <<-PWSH
      $appgw   = '${module.application_gateway.application_gateway_name}'
      $rg      = '${module.resource_group.name}'
      $maxTry  = 15
      $approved = $false

      for ($i = 1; $i -le $maxTry; $i++) {
        Write-Host "[$i/$maxTry] Checking for pending private endpoint connections on $appgw..."

        $ids = az network private-endpoint-connection list `
          --name $appgw `
          --resource-group $rg `
          --type Microsoft.Network/applicationGateways `
          --query "[?properties.privateLinkServiceConnectionState.status=='Pending'][].id" `
          --output tsv 2>$null

        if ($ids) {
          foreach ($id in ($ids -split "`n" | Where-Object { $_.Trim() })) {
            Write-Host "Approving connection: $id"
            az network private-endpoint-connection approve `
              --id $id `
              --description "Auto-approved by Terraform" | Out-Null
          }
          Write-Host "Private endpoint connection(s) approved successfully."
          $approved = $true
          break
        }

        if ($i -lt $maxTry) {
          Write-Host "No pending connections found yet. Waiting 20 seconds..."
          Start-Sleep -Seconds 20
        }
      }

      if (-not $approved) {
        Write-Warning "No pending private endpoint connections found after $maxTry attempts ($($maxTry * 20) seconds). Approve manually if needed."
      }
    PWSH
  }

  depends_on = [azapi_resource.appgw_private_origin, azurerm_cdn_frontdoor_route.private_link]
}
