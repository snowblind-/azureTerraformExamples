# Required variables
custom_image_id = "/subscriptions/YOUR-SUBSCRIPTION-ID/resourceGroups/YOUR-IMAGE-RG/providers/Microsoft.Compute/images/YOUR-IMAGE-NAME"
instance_type   = "Standard_DS4_v2"
admin_password  = "CHANGEME"

# Optional - customize as needed
resource_group_name = "bigip-rg"
location           = "West US"
admin_username     = "azureadmin"

# Optional - use SSH key instead of password
use_ssh_key    = false
ssh_public_key = ""  # Set to your public key if use_ssh_key = true
