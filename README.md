# Azure Key Vault + GitHub OIDC + AKS CSI Complete Setup Guide

![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![Azure](https://img.shields.io/badge/azure-%230072C6.svg?style=for-the-badge&logo=microsoftazure&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)

---

# 📌 Overview

This repository manages Azure Key Vault infrastructure and application secret automation for AKS workloads using:

- Terraform
- Azure Key Vault
- Azure RBAC
- GitHub Actions OIDC
- AKS Key Vault CSI Driver
- GitHub Secrets
- Stakater Reloader

The goal is to securely deliver application secrets into AKS workloads without:

- storing plaintext secrets inside Terraform state
- committing `.env` files into Git repositories
- manually creating Kubernetes Secret manifests
- using static Azure credentials

---

# ⚙️ High-Level Architecture

```text
GitHub Secrets
    ↓
GitHub Actions (OIDC Authentication)
    ↓
Terraform
    ↓
Azure Key Vault

AKS Pod
    ↓
Secrets Store CSI Driver
    ↓
AKS Managed Identity
    ↓
Azure Key Vault
    ↓
Secret Mounted Into Pod Filesystem
    ↓
(Optional) Kubernetes Secret Sync
    ↓
(Optional) Stakater Reloader
```

---

# 📂 Repository Structure

```text
.
├── providers.tf
├── variables.tf
├── keyvault.tf
├── outputs.tf
├── terraform.tfvars
├── secrets-map.json
└── .github/
    └── workflows/
        └── terraform-deploy.yml
```

---

# 🔐 Authentication Flow

This setup uses GitHub Actions OpenID Connect (OIDC) authentication.

Benefits:

- No Azure Client Secret
- No static credentials
- Temporary authentication tokens
- Azure-native authentication flow
- More secure CI/CD pipeline

---

# 1. Create GitHub OIDC Identity

## Environment Variables

```bash
export SUBSCRIPTION_ID="6f48750e-5037-4321-9d8b-a9e58c87accf"
export TENANT_ID="6260daf3-8575-4ac3-bec1-844ebcae1c64"

export GITHUB_ORG="Maharbawga"
export GITHUB_REPO="terraform-key-vault"

export APP_NAME="github-actions-terraform-keyvault"

export TFSTATE_RG="tfstate-rg"
export TFSTATE_STORAGE="mbftfstatestorage"

export KEYVAULT_RG="keyvault-management"
```

## Create Azure AD Application

```bash
az ad app create --display-name $APP_NAME
```

## Get Application Client ID

```bash
export APP_ID=$(az ad app list \
  --display-name $APP_NAME \
  --query "[0].appId" -o tsv)
```

## Create Service Principal

```bash
az ad sp create --id $APP_ID
```

## Get Service Principal Object ID

```bash
export SP_OBJECT_ID=$(az ad sp show \
  --id $APP_ID \
  --query id -o tsv)
```

## Create Federated Credential

```bash
az ad app federated-credential create \
  --id $APP_ID \
  --parameters "{
    \"name\": \"github-main\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
```

---

# 2. Assign Azure RBAC Permissions

## Contributor

```bash
az role assignment create \
  --assignee "$SP_OBJECT_ID" \
  --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$KEYVAULT_RG"
```

## User Access Administrator

```bash
az role assignment create \
  --assignee "$SP_OBJECT_ID" \
  --role "User Access Administrator" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$KEYVAULT_RG"
```

## Terraform Backend Storage Access

```bash
az role assignment create \
  --assignee "$SP_OBJECT_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "$(az storage account show \
    --name "$TFSTATE_STORAGE" \
    --resource-group "$TFSTATE_RG" \
    --query id \
    -o tsv)"
```

---

# 3. Terraform Backend Configuration

## providers.tf

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "mbftfstatestorage"
    container_name       = "tfstate"
    key                  = "keyvault.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}
```

---

# 4. Terraform Variables

## terraform.tfvars

```hcl
tenant_id = "6260daf3-8575-4ac3-bec1-844ebcae1c64"

aks_keyvault_csi_object_id = "657353f9-2bbc-43d6-8459-fc1223b5328d"

envs = {
  dev = {
    kv_name = "kv-dev"
  }

  uat = {
    kv_name = "kv-uat"
  }

  production = {
    kv_name = "kv-production"
  }
}
```

---

# 5. Key Vault RBAC

## GitHub Actions Terraform Identity

```hcl
resource "azurerm_role_assignment" "github_keyvault_admin" {
  for_each = azurerm_key_vault.kv

  scope                = each.value.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "ServicePrincipal"

  skip_service_principal_aad_check = true
}
```

This Role Assignment gives GitHub Actions OIDC Identity full administrative access to Azure Key Vault.

---

## AKS CSI Driver Identity

```hcl
resource "azurerm_role_assignment" "aks_csi_keyvault_secrets_user" {
  for_each = azurerm_key_vault.kv

  scope                = each.value.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.aks_keyvault_csi_object_id
  principal_type       = "ServicePrincipal"

  skip_service_principal_aad_check = true
}
```

This Role Assignment gives AKS CSI Driver permission to read Key Vault secrets.

---

# ⚠️ Important ID Difference

## SecretProviderClass

```yaml
userAssignedIdentityID
```

expects:

```text
Client ID
```

Example:

```text
b076294c-9ab2-4984-9225-097194239388
```

---

## Terraform Role Assignment

```hcl
principal_id
```

expects:

```text
Object ID / Principal ID
```

Example:

```text
657353f9-2bbc-43d6-8459-fc1223b5328d
```

---

# 6. Secret Management Strategy

Application `.env` values are stored securely inside GitHub Actions Secrets.

Example:

```text
DEV_EXCHANGE_BACKEND_ENV
UAT_EXCHANGE_BACKEND_ENV
PRODUCTION_EXCHANGE_BACKEND_ENV
```

Each GitHub Secret contains full `.env` file content.

---

# 7. GitHub Actions Workflow

## terraform-deploy.yml

```yaml
name: Terraform Deploy

on:
  push:
    branches: [ main ]

permissions:
  id-token: write
  contents: read

jobs:
  terraform:
    name: Terraform Plan & Apply
    runs-on: ubuntu-latest

    env:
      ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
      ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}

      ARM_USE_OIDC: true
      ARM_USE_AZUREAD: true

      TF_VAR_tenant_id: ${{ secrets.AZURE_TENANT_ID }}
      TF_VAR_aks_keyvault_csi_object_id: ${{ secrets.AKS_KEYVAULT_CSI_OBJECT_ID }}

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: terraform init

      - name: Terraform Validate
        run: terraform validate

      - name: Terraform Plan
        run: terraform plan -out=main.tfplan

      - name: Terraform Apply
        run: terraform apply -auto-approve main.tfplan

      - name: Upload Secrets To Azure Key Vault
        env:
          DEV_EXCHANGE_BACKEND_ENV: ${{ secrets.DEV_EXCHANGE_BACKEND_ENV }}
          DEV_MBR_GREY_BACKEND_ENV: ${{ secrets.DEV_MBR_GREY_BACKEND_ENV }}
          DEV_MBR_INTEGRATION_ENV: ${{ secrets.DEV_MBR_INTEGRATION_ENV }}
          DEV_MBR_OPERATION_ENV: ${{ secrets.DEV_MBR_OPERATION_ENV }}

          UAT_EXCHANGE_BACKEND_ENV: ${{ secrets.UAT_EXCHANGE_BACKEND_ENV }}
          UAT_MBR_GREY_BACKEND_ENV: ${{ secrets.UAT_MBR_GREY_BACKEND_ENV }}
          UAT_MBR_INTEGRATION_ENV: ${{ secrets.UAT_MBR_INTEGRATION_ENV }}
          UAT_MBR_OPERATION_ENV: ${{ secrets.UAT_MBR_OPERATION_ENV }}

          PRODUCTION_EXCHANGE_BACKEND_ENV: ${{ secrets.PRODUCTION_EXCHANGE_BACKEND_ENV }}
          PRODUCTION_INTEGRATION_ENV: ${{ secrets.PRODUCTION_INTEGRATION_ENV }}
          PRODUCTION_MBR_GREY_BACKEND_ENV: ${{ secrets.PRODUCTION_MBR_GREY_BACKEND_ENV }}
          PRODUCTION_RRS_BACKEND_ENV: ${{ secrets.PRODUCTION_RRS_BACKEND_ENV }}

        run: |
          jq -c '.[]' secrets-map.json | while read item; do
            VAULT=$(echo "$item" | jq -r '.vault')
            SECRET_NAME=$(echo "$item" | jq -r '.secretName')
            GITHUB_SECRET=$(echo "$item" | jq -r '.githubSecret')

            SECRET_VALUE="${!GITHUB_SECRET}"

            if [ -z "$SECRET_VALUE" ]; then
              echo "Missing GitHub secret: $GITHUB_SECRET"
              exit 1
            fi

            echo "Uploading secret: $SECRET_NAME to vault: $VAULT"

            az keyvault secret set \
              --vault-name "$VAULT" \
              --name "$SECRET_NAME" \
              --value "$SECRET_VALUE" \
              --output none
          done
```

---

# 8. GitHub Repository Secrets

Required GitHub Secrets:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
AKS_KEYVAULT_CSI_OBJECT_ID
```

Application Secrets:

```text
DEV_EXCHANGE_BACKEND_ENV
DEV_MBR_GREY_BACKEND_ENV
DEV_MBR_INTEGRATION_ENV
DEV_MBR_OPERATION_ENV

UAT_EXCHANGE_BACKEND_ENV
UAT_MBR_GREY_BACKEND_ENV
UAT_MBR_INTEGRATION_ENV
UAT_MBR_OPERATION_ENV

PRODUCTION_EXCHANGE_BACKEND_ENV
PRODUCTION_INTEGRATION_ENV
PRODUCTION_MBR_GREY_BACKEND_ENV
PRODUCTION_RRS_BACKEND_ENV
```

Each application secret contains the full `.env` file content.

---

# 9. Security Benefits

This architecture provides:

* No plaintext secrets inside Terraform
* No sensitive IDs stored inside `terraform.tfvars`
* No secrets committed into Git repositories
* No Kubernetes Secret YAML files committed
* OIDC-based authentication
* Azure-native RBAC authorization
* Centralized secret management
* Automatic pod secret refresh
* Temporary authentication tokens instead of static credentials
