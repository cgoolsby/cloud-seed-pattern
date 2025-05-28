# AWS Multi-Account Setup

This Terraform module creates AWS accounts and automatically populates Kubernetes ConfigMaps for use with Crossplane.

## Prerequisites

- Your EKS cluster must be running (created by `terraform/eks`)
- AWS credentials with permissions to create Organizations and accounts

## Quick Start

```bash
cd terraform/accounts

# First time setup
terraform init
cp accounts.example.tfvars accounts.tfvars
# Edit accounts.tfvars with your account details

# If you don't have an AWS Organization yet
terraform apply -var="create_organization=true" -var-file="accounts.tfvars"

# For subsequent runs (adding new accounts)
terraform apply -var-file="accounts.tfvars"
```

## How It Works

1. Creates AWS accounts in your Organization
2. Creates individual ConfigMaps for each account in `crossplane-system` namespace
3. Creates a master registry ConfigMap with all accounts
4. Integrates with Crossplane IRSA authentication for cross-account access

Note: Account aliases are not automatically created to keep the setup simpler.

## ConfigMap Structure

Each account gets its own ConfigMap:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-account-mycompany-dev
  namespace: crossplane-system
data:
  ACCOUNT_ID: "123456789012"
  ACCOUNT_NAME: "MyCompany Development"
  ACCOUNT_ALIAS: "mycompany-dev"
  ENVIRONMENT: "development"
  ASSUME_ROLE_ARN: "arn:aws:iam::123456789012:role/OrganizationAccountAccessRole"
```

## Using with Crossplane

Create ProviderConfigs that reference these ConfigMaps:

```yaml
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: account-dev
spec:
  credentials:
    source: InjectedIdentity
  assumeRoleARN: "arn:aws:iam::123456789012:role/OrganizationAccountAccessRole"
```

Note: Currently, ProviderConfig assumeRoleARN field requires a static string. 
To use ConfigMap values, you would need to use tools like Kustomize or Helm 
to substitute values during deployment.

## Adding New Accounts

1. Edit `accounts.tfvars`:
```hcl
accounts = {
  # ... existing accounts ...
  
  "mycompany-newaccount" = {
    name        = "MyCompany New Account"
    email       = "aws-newaccount@mycompany.com"
    environment = "development"
  }
}
```

2. Apply Terraform:
```bash
terraform apply -var-file="accounts.tfvars"
```

3. ConfigMaps are automatically created and Flux will sync them

## Important Notes

- Each AWS account needs a unique email address
- The OrganizationAccountAccessRole is created automatically by AWS Organizations
- ConfigMaps are created in the management cluster only
- **Account Deletion**: AWS accounts created via Organizations cannot be automatically deleted by Terraform due to AWS constraints. Manual steps are required to close accounts.
- **Email Access**: Ensure you have access to the email addresses used, as AWS may send important notifications there
- **Billing**: New accounts inherit billing settings from the Organization master account