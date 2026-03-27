# Import block for the existing Front Door profile that was created
# outside of Terraform state due to a provider timeout.
# Uncomment the block below if terraform apply fails with "Resource already exists"
# and the profile exists in Azure but not in Terraform state.
#
# import {
#   to = module.front_door.azapi_resource.front_door_profile
#   id = "/subscriptions/<subscription-id>/resourceGroups/<rg-name>/providers/Microsoft.Cdn/profiles/<afd-name>"
# }
