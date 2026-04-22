# Azure Key Vault Secret Management & AKS Automation

![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![Azure](https://img.shields.io/badge/azure-%230072C6.svg?style=for-the-badge&logo=microsoftazure&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)

## 📌 Project Overview
This repository manages the lifecycle of application environment variables for the **MBR Project** infrastructure. It automates the synchronization of local `.env` files into **Azure Key Vault** using Terraform and ensures that updates are live-reloaded into **Azure Kubernetes Service (AKS)** pods without manual intervention.

## ⚙️ Architecture & Flow

The integration follows a "GitOps-style" secret management flow:

1.  **Secret Definition**: Secrets are stored in environment-specific directories (`secrets/dev`, `secrets/uat`, `secrets/production`).
2.  **IaC Processing**: Terraform dynamically iterates through these directories, creating a flattened map of secrets.
3.  **Cloud Storage**: Secrets are pushed to Azure Key Vault instances with **RBAC Authorization** enabled.
4.  **K8s Integration**: The **Azure Key Vault Secret Store CSI Driver** (or External Secrets Operator) maps these Vault secrets into native Kubernetes Secret objects.
5.  **Auto-Reload**: The **Stakater Reloader** controller watches these Kubernetes Secrets. When a change is detected, it performs a rolling update of the associated Deployments.

## 📂 Directory Structure

```text
.
├── main.tf                # Provider and Backend configuration
├── keyvault.tf            # Logic for Vaults, RBAC, and Secret creation
├── variables.tf           # Environment maps and Tenant IDs
├── secrets/               # Source of truth for application secrets
│   ├── dev/
│   │   ├── exchange-backend.env
│   │   ├── integration.env
│   │   └── payment-approval-backend.env
│   ├── uat/
│   └── production/
└── .github/workflows/     # CI/CD pipelines (OIDC Auth)
```
---

## 🛠 Terraform Implementation

1. Dynamic Secret Mapping

We use a nested loop with fileset and flatten to ensure that adding a new .env file to a folder automatically creates a new secret in the correct Key Vault.

```hcl
locals {
  all_files = flatten([
    for env in keys(var.envs) : [
      for file in fileset("${path.module}/secrets/${env}", "*.env") : {
        key      = "${replace(file, ".env", "")}-${env}"
        env_name = env
        app_name = "${replace(file, ".env", "")}-${env}"
        filepath = "${path.module}/secrets/${env}/${file}"
      }
    ]
  ])

  secret_map = {
    for item in local.all_files : item.key => {
      env_name    = item.env_name
      secret_name = item.app_name
      raw_content = file(item.filepath)
    }
  }
}
```

2. RBAC Enforcement (Audit Ready)

To comply with Central Bank of Myanmar (CBM) Regulatory Audits, we avoid legacy Access Policies. We use Azure RBAC to grant the Key Vault Administrator role dynamically to the executing identity (User or GitHub Service Principal).

---

## 🔄 Automatic Pod Reloading (Stakater Reloader)
To achieve zero-downtime configuration updates, we use the Stakater Reloader controller. The applications are configured to watch their specific secret mounts.

### Deployment Annotation
In your Helm charts or Deployment manifests, include the following annotation to link the pod lifecycle to the secret:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  annotations:
      secret.reloader.stakater.com/reload: "my-app-secret"
spec:
  template:
    metadata:
```    

### 🚀 CI/CD Pipeline
The pipeline is hosted on GitHub Actions and uses OIDC (OpenID Connect) for secure authentication to Azure.

 1. Identity: The runner assumes a Service Principal identity via a Federated Credential.
 2. Detection: Terraform detects the ServicePrincipal type and assigns the necessary Key Vault roles to itself to perform the "Read/Write" operations.
 3. Execution:
    - terraform plan -out=main.tfplan
    - terraform apply main.tfplan

### 📖 Operational Guide
Adding a New Secret

1. Create a new file: secrets/dev/new-service.env.
2. Add your key-value pairs inside the file.
3. Commit and push:    

```bash
git add .
git commit -m "feat: add new-service secrets to dev"
git push origin main
```

## Troubleshooting 403/409 Errors

- 403 Forbidden: Usually means the role assignment hasn't propagated or the principal_id is incorrect. Ensure principal_type matches the identity (User vs ServicePrincipal).

- 409 Conflict: Occurs if a role assignment exists in Azure but not in the Terraform state. Use terraform import to sync.