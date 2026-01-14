# F5 BIG-IP Azure Deployment with Terraform

Deploy F5 BIG-IP in Azure with dual network interfaces using a custom image. This guide covers the complete setup from Azure CLI installation through Terraform deployment.

## Overview

This Terraform template deploys an F5 BIG-IP instance in Azure with:
- **Two network interfaces** (Management and External)
- **Two separate subnets** with dedicated address spaces
- **Network Security Groups** for each interface
- **Public IPs** for both management and external access
- **Custom BIG-IP image** support
- **Flexible authentication** (password or SSH key)

## Prerequisites

- Azure subscription with appropriate permissions
- Azure CLI
- Terraform (>= 1.0)
- Custom F5 BIG-IP VHD image

## Setup Guide

### 1. Install Azure CLI

**Windows:**
```bash
winget install -e --id Microsoft.AzureCLI
```

**macOS:**
```bash
brew install azure-cli
```

**Linux:**
```bash
curl -sL https://aka.ms/InstallAzureCLI | sudo bash
```

### 2. Authenticate with Azure

```bash
# Login to Azure
az login

# Set your subscription (if you have multiple)
az account list --output table
az account set --subscription "Your-Subscription-Name"

# Verify current subscription
az account show
```

### 3. Upload Custom BIG-IP Image

#### Prepare the VHD Image

Your VHD file must be aligned to 512-byte boundaries. If you are using a standard image from downloads.f5.com you should be fine once you extract the .vhd, if you customize that image with image builder you may want to double check before uploading. Check and resize if needed:

```bash
# Check current size
ls -l /path/to/bigip.vhd

# Calculate aligned size using Python
python3 << EOF
import math
current_size = $(stat -c%s /path/to/bigip.vhd)  # Linux
# current_size = $(stat -f%z /path/to/bigip.vhd)  # macOS
boundary = 512
aligned_size = math.ceil(current_size / boundary) * boundary
print(f"Resize to: {aligned_size}")
EOF

# Resize if needed
qemu-img resize /path/to/bigip.vhd <aligned_size>
```

#### Create Storage Account and Upload

```bash
# Create resource group for images
az group create --name images-rg --location eastus

# Create storage account (name must be globally unique)
az storage account create \
  --resource-group images-rg \
  --name yourstorageaccount \
  --location eastus \
  --sku Standard_LRS

# Get storage account key
STORAGE_KEY=$(az storage account keys list \
  --resource-group images-rg \
  --account-name yourstorageaccount \
  --query "[0].value" -o tsv)

# Create container
az storage container create \
  --account-name yourstorageaccount \
  --name images \
  --account-key $STORAGE_KEY

# Upload VHD (this may take some time)
az storage blob upload \
  --account-name yourstorageaccount \
  --account-key $STORAGE_KEY \
  --container-name images \
  --type page \
  --file /path/to/bigip.vhd \
  --name bigip.vhd
```

#### Create Managed Image

```bash
# Get blob URL
BLOB_URL=$(az storage blob url \
  --account-name yourstorageaccount \
  --container-name images \
  --name bigip.vhd \
  --output tsv)

# Create managed image
az image create \
  --resource-group images-rg \
  --name bigip-custom-image \
  --os-type Linux \
  --source $BLOB_URL \
  --location eastus

# Get image ID for Terraform
az image show \
  --resource-group images-rg \
  --name bigip-custom-image \
  --query id \
  --output tsv
```

### 4. Configure Terraform

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required Variables
custom_image_id = "/subscriptions/YOUR-SUBSCRIPTION-ID/resourceGroups/images-rg/providers/Microsoft.Compute/images/bigip-custom-image"
instance_type   = "Standard_DS4_v2"
admin_password  = "YourSecurePassword123!"

# Optional Variables
resource_group_name = "bigip-rg"
location           = "East US"
admin_username     = "azureuser"

# Network Configuration (optional)
vnet_address_space    = ["10.0.0.0/16"]
mgmt_subnet_prefix    = "10.0.1.0/24"
external_subnet_prefix = "10.0.2.0/24"

# SSH Key Authentication (optional)
use_ssh_key    = false
ssh_public_key = ""
```

**Important:** Never commit `terraform.tfvars` containing passwords to version control. Add it to `.gitignore`.

### 5. Deploy with Terraform

```bash
# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Deploy the infrastructure
terraform apply

# When prompted, type 'yes' to confirm
```

### 6. Access Your BIG-IP Instance

After deployment completes, Terraform will output:

```
bigip_mgmt_public_ip    = "x.x.x.x"
bigip_external_public_ip = "y.y.y.y"
bigip_mgmt_url          = "https://x.x.x.x"
```

Access the BIG-IP management interface at `https://<mgmt_public_ip>`

## File Structure

```
.
├── main.tf              # Terraform configuration
├── terraform.tfvars     # Your configuration values (DO NOT COMMIT)
├── .gitignore           # Exclude sensitive files
└── README.md            # This file
```

## Configuration Options

### VM Sizes

Common Azure VM sizes for BIG-IP:
- `Standard_DS3_v2` - 4 vCPUs, 14 GB RAM
- `Standard_DS4_v2` - 8 vCPUs, 28 GB RAM (recommended)
- `Standard_DS5_v2` - 16 vCPUs, 56 GB RAM
- `Standard_F8s_v2` - 8 vCPUs, 16 GB RAM (compute optimized)

### Authentication Methods

**Password Authentication (default):**
```hcl
use_ssh_key = false
admin_password = "YourSecurePassword123!"
```

**SSH Key Authentication (recommended for production):**
```hcl
use_ssh_key = true
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2E..."
admin_password = ""  # Not used when SSH key is enabled
```

## Network Architecture

```
┌─────────────────────────────────────────┐
│           Azure Virtual Network         │
│                                         │
│  ┌──────────────┐  ┌─────────────────┐ │
│  │   Mgmt       │  │    External     │ │
│  │   Subnet     │  │    Subnet       │ │
│  │ 10.0.1.0/24  │  │  10.0.2.0/24    │ │
│  └──────┬───────┘  └────────┬────────┘ │
│         │                   │          │
│         │                   │          │
│  ┌──────▼───────────────────▼────────┐ │
│  │       BIG-IP VM (2 NICs)         │ │
│  │   - Management Interface         │ │
│  │   - External Interface           │ │
│  └──────────────────────────────────┘ │
│                                         │
└─────────────────────────────────────────┘
         │                   │
         │                   │
    Public IP           Public IP
   (Management)         (External)
```

## Security Considerations

1. **Network Security Groups** are configured with basic rules:
   - Management: SSH (22), HTTPS (443)
   - External: HTTP (80), HTTPS (443)
   
2. **Customize NSG rules** in `main.tf` to match your security requirements

3. **Use SSH keys** instead of passwords for production deployments

4. **Restrict source IPs** in NSG rules to known management networks

## Troubleshooting

### VHD Upload Issues

**Error: Invalid page blob size**
- VHD must be aligned to 512-byte boundaries
- Use the resize commands in step 3 to fix alignment

**Error: Slow upload speeds**
- Consider using AzCopy for faster uploads of large files
- Use Azure Cloud Shell which has better bandwidth to Azure storage

### Terraform Deployment Issues

**Error: Marketplace terms not accepted**
- This template uses custom images, no marketplace terms needed
- Ensure your `custom_image_id` is correct

**Error: Image not found**
- Verify image exists: `az image show --ids <your-image-id>`
- Ensure image is in the same region as deployment

**Error: VM size not available**
- Check available sizes in your region: `az vm list-sizes --location eastus`
- Some sizes require quota increases

## Cleanup

To destroy all resources created by Terraform:

```bash
terraform destroy
```

To also remove the uploaded image:

```bash
az image delete --resource-group images-rg --name bigip-custom-image
az group delete --name images-rg --yes --no-wait
```

## Additional Resources

- [Azure CLI Documentation](https://docs.microsoft.com/en-us/cli/azure/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [F5 BIG-IP Documentation](https://my.f5.com/manage/s/article/K86011692)
- [Azure VM Sizes](https://docs.microsoft.com/en-us/azure/virtual-machines/sizes)

## License

This template is provided as-is for educational and deployment purposes.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.
