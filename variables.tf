variable "location" {
  type        = string
  description = "The Azure region where resources will be deployed."
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.location))
    error_message = "The location must only contain lowercase letters, numbers, and hyphens."
  }
}

variable "resource_name_location_short" {
  type        = string
  description = "The short name segment for the location. Auto-detected from region geo_code if empty."
  default     = ""
  validation {
    condition     = length(var.resource_name_location_short) == 0 || can(regex("^[a-z]+$", var.resource_name_location_short))
    error_message = "Must only contain lowercase letters."
  }
  validation {
    condition     = length(var.resource_name_location_short) <= 3
    error_message = "Must be 3 characters or less."
  }
}

variable "resource_name_workload" {
  type        = string
  description = "The name segment for the workload."
  default     = "fw"
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.resource_name_workload))
    error_message = "Must only contain lowercase letters and numbers."
  }
  validation {
    condition     = length(var.resource_name_workload) <= 4
    error_message = "Must be 4 characters or less."
  }
}

variable "resource_name_environment" {
  type        = string
  description = "The name segment for the environment."
  default     = "dev"
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.resource_name_environment))
    error_message = "Must only contain lowercase letters and numbers."
  }
  validation {
    condition     = length(var.resource_name_environment) <= 4
    error_message = "Must be 4 characters or less."
  }
}

variable "resource_name_sequence_start" {
  type        = number
  description = "The sequence number for resource names."
  default     = 1
  validation {
    condition     = var.resource_name_sequence_start >= 1 && var.resource_name_sequence_start <= 999
    error_message = "Must be between 1 and 999."
  }
}

variable "resource_name_templates" {
  type        = map(string)
  description = "A map of resource name templates using templatestring syntax."
  default = {
    resource_group_name          = "rg-$${workload}-$${environment}-$${location}-$${sequence}"
    log_analytics_workspace_name = "law-$${workload}-$${environment}-$${location}-$${sequence}"
    virtual_network_name         = "vnet-$${workload}-$${environment}-$${location}-$${sequence}"
    public_ip_name               = "pip-fw-$${workload}-$${environment}-$${location}-$${sequence}"
    firewall_name                = "fw-$${workload}-$${environment}-$${location}-$${sequence}"
    firewall_policy_name         = "fwpol-$${workload}-$${environment}-$${location}-$${sequence}"
    nat_gateway_name             = "nat-$${workload}-$${environment}-$${location}-$${sequence}"
    nat_gateway_public_ip_name   = "pip-nat-$${workload}-$${environment}-$${location}-$${sequence}"
    spoke_virtual_network_name   = "vnet-spoke-$${workload}-$${environment}-$${location}-$${sequence}"
    spoke_route_table_name       = "rt-spoke-$${workload}-$${environment}-$${location}-$${sequence}"
    appgw_name                   = "agw-$${workload}-$${environment}-$${location}-$${sequence}"
    appgw_public_ip_name         = "pip-agw-$${workload}-$${environment}-$${location}-$${sequence}"
    front_door_name              = "afd-$${workload}-$${environment}-$${sequence}"
    waf_front_door_policy_name   = "wafpol-afd-$${workload}-$${environment}-$${sequence}"
    waf_appgw_policy_name        = "wafpol-agw-$${workload}-$${environment}-$${location}-$${sequence}"
    appgw_pvtlink_config_name    = "pvtlink-$${workload}-$${environment}-$${sequence}"
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to add to all resources."
  default = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Purpose     = "AzureFirewall"
  }
}

variable "address_space" {
  type        = string
  description = "The address space for the virtual network (e.g. 10.0.0.0/16)."
  default     = "10.0.0.0/16"
}

variable "firewall_subnet_address_prefix" {
  type        = string
  description = "The address prefix for the AzureFirewallSubnet. Minimum /26 required."
  default     = "10.0.1.0/26"
}

variable "firewall_sku_name" {
  type        = string
  description = "SKU name of the Firewall. Possible values are AZFW_Hub and AZFW_VNet."
  default     = "AZFW_VNet"
  validation {
    condition     = contains(["AZFW_Hub", "AZFW_VNet"], var.firewall_sku_name)
    error_message = "Must be either AZFW_Hub or AZFW_VNet."
  }
}

variable "firewall_sku_tier" {
  type        = string
  description = "SKU tier of the Firewall. Possible values are Premium, Standard, and Basic."
  default     = "Standard"
  validation {
    condition     = contains(["Premium", "Standard", "Basic"], var.firewall_sku_tier)
    error_message = "Must be Premium, Standard, or Basic."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "A list of availability zones for the firewall and public IP."
  default     = ["1", "2", "3"]
}

variable "firewall_private_ip_ranges" {
  type        = set(string)
  description = "A list of SNAT private CIDR IP ranges, or IANAPrivateRanges."
  default     = null
}

# ---------------------------------------------------------------------------
# Firewall Rule Collections
# ---------------------------------------------------------------------------
variable "network_rule_collections" {
  type = map(object({
    priority = number
    action   = string
    rules = list(object({
      name                  = string
      protocols             = list(string)
      source_addresses      = list(string)
      destination_addresses = list(string)
      destination_ports     = list(string)
    }))
  }))
  description = "A map of network rule collections for the firewall policy."
  default = {
    allow-dns = {
      priority = 1000
      action   = "Allow"
      rules = [
        {
          name                  = "allow-dns"
          protocols             = ["UDP"]
          source_addresses      = ["10.0.0.0/16"]
          destination_addresses = ["*"]
          destination_ports     = ["53"]
        }
      ]
    }
    allow-ntp = {
      priority = 1100
      action   = "Allow"
      rules = [
        {
          name                  = "allow-ntp"
          protocols             = ["UDP"]
          source_addresses      = ["10.0.0.0/16"]
          destination_addresses = ["*"]
          destination_ports     = ["123"]
        }
      ]
    }
  }
}

variable "application_rule_collections" {
  type = map(object({
    priority = number
    action   = string
    rules = list(object({
      name              = string
      source_addresses  = list(string)
      destination_fqdns = list(string)
      protocols = list(object({
        type = string
        port = number
      }))
    }))
  }))
  description = "A map of application rule collections for the firewall policy."
  default = {
    allow-web = {
      priority = 1000
      action   = "Allow"
      rules = [
        {
          name              = "allow-microsoft"
          source_addresses  = ["10.0.0.0/16"]
          destination_fqdns = ["*.microsoft.com", "*.azure.com", "*.windows.net"]
          protocols = [
            { type = "Https", port = 443 }
          ]
        },
        {
          name              = "allow-updates"
          source_addresses  = ["10.0.0.0/16"]
          destination_fqdns = ["*.ubuntu.com", "*.windowsupdate.com"]
          protocols = [
            { type = "Https", port = 443 },
            { type = "Http", port = 80 }
          ]
        }
      ]
    }
  }
}

# ---------------------------------------------------------------------------
# Spoke VNet
# ---------------------------------------------------------------------------
variable "spoke_appgw_subnet_address_prefix" {
  type        = string
  description = "The address prefix for the Application Gateway subnet in the spoke VNet. Minimum /26 required."
  default     = "10.1.2.0/24"
}

variable "appgw_capacity" {
  type        = number
  description = "The number of Application Gateway capacity units (fixed scale)."
  default     = 2
  validation {
    condition     = var.appgw_capacity >= 1 && var.appgw_capacity <= 125
    error_message = "Capacity must be between 1 and 125."
  }
}

variable "spoke_address_space" {
  type        = string
  description = "The address space for the spoke virtual network."
  default     = "10.1.0.0/16"
}

variable "spoke_workload_subnet_address_prefix" {
  type        = string
  description = "The address prefix for the workload subnet in the spoke VNet."
  default     = "10.1.1.0/24"
}

# ---------------------------------------------------------------------------
# Private Link Options (Pattern 2: Front Door Premium → AppGW via Private Link)
# ---------------------------------------------------------------------------

variable "enable_appgw_private_link" {
  type = bool
  description = <<-EOT
    Enable Pattern 2: Front Door Premium → Application Gateway via Private Link (most secure).
    When true:
      - A dedicated /29 Private Link service subnet is added to the spoke VNet.
      - An AppGW Private Link configuration is created on the private frontend IP.
      - Front Door connects to AppGW via a managed Private Endpoint — no public traffic reaches AppGW directly.
    Workflow after enabling:
      1. Run terraform apply.
      2. In Azure Portal → Application Gateway → Settings → Private Link
         → Private endpoint connections → Approve the pending request from Front Door.
      3. Wait ~2 minutes for the connection to establish. Front Door then routes privately.
    Note: Cannot be changed from false→true in-place without destroying the module-managed
    Front Door origin + route (Terraform handles this automatically during apply).
  EOT
  default = false
}

variable "appgw_private_link_subnet_prefix" {
  type        = string
  description = "Address prefix for the dedicated Private Link service subnet in the spoke VNet. Minimum /29. Only used when enable_appgw_private_link = true."
  default     = "10.1.3.0/29"
  validation {
    condition     = can(cidrhost(var.appgw_private_link_subnet_prefix, 0))
    error_message = "Must be a valid CIDR prefix (e.g. 10.1.3.0/29)."
  }
}

variable "appgw_private_frontend_ip" {
  type        = string
  description = "Static private IP for the AppGW private frontend IP configuration. Must fall within var.spoke_appgw_subnet_address_prefix. Only used when enable_appgw_private_link = true."
  default     = "10.1.2.200"
  validation {
    condition     = can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", var.appgw_private_frontend_ip))
    error_message = "Must be a valid IPv4 address."
  }
}

variable "dnat_rule_collections" {
  type = map(object({
    priority = number
    rules = list(object({
      name                = string
      protocols           = list(string)
      source_addresses    = list(string)
      destination_address = string
      destination_ports   = list(string)
      translated_address  = string
      translated_port     = string
    }))
  }))
  description = "A map of DNAT rule collections for the firewall policy. Set to {} to skip."
  default     = {}
}
