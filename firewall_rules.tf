resource "azurerm_firewall_policy_rule_collection_group" "network" {
  name               = "rcg-network"
  firewall_policy_id = module.firewall_policy.resource_id
  priority           = 200

  dynamic "network_rule_collection" {
    for_each = var.network_rule_collections
    content {
      name     = network_rule_collection.key
      priority = network_rule_collection.value.priority
      action   = network_rule_collection.value.action

      dynamic "rule" {
        for_each = network_rule_collection.value.rules
        content {
          name                  = rule.value.name
          protocols             = rule.value.protocols
          source_addresses      = rule.value.source_addresses
          destination_addresses = rule.value.destination_addresses
          destination_ports     = rule.value.destination_ports
        }
      }
    }
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "application" {
  name               = "rcg-application"
  firewall_policy_id = module.firewall_policy.resource_id
  priority           = 300

  dynamic "application_rule_collection" {
    for_each = var.application_rule_collections
    content {
      name     = application_rule_collection.key
      priority = application_rule_collection.value.priority
      action   = application_rule_collection.value.action

      dynamic "rule" {
        for_each = application_rule_collection.value.rules
        content {
          name              = rule.value.name
          source_addresses  = rule.value.source_addresses
          destination_fqdns = rule.value.destination_fqdns

          dynamic "protocols" {
            for_each = rule.value.protocols
            content {
              type = protocols.value.type
              port = protocols.value.port
            }
          }
        }
      }
    }
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "dnat" {
  count = length(var.dnat_rule_collections) > 0 ? 1 : 0

  name               = "rcg-dnat"
  firewall_policy_id = module.firewall_policy.resource_id
  priority           = 100

  dynamic "nat_rule_collection" {
    for_each = var.dnat_rule_collections
    content {
      name     = nat_rule_collection.key
      priority = nat_rule_collection.value.priority
      action   = "Dnat"

      dynamic "rule" {
        for_each = nat_rule_collection.value.rules
        content {
          name                = rule.value.name
          protocols           = rule.value.protocols
          source_addresses    = rule.value.source_addresses
          destination_address = rule.value.destination_address
          destination_ports   = rule.value.destination_ports
          translated_address  = rule.value.translated_address
          translated_port     = rule.value.translated_port
        }
      }
    }
  }
}
