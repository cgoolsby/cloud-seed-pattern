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
2. Sets up account aliases automatically
3. Creates individual ConfigMaps for each account in `crossplane-system` namespace
4. Creates a master registry ConfigMap with all accounts

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
  assumeRoleARN: # Reference from ConfigMap
    source: ConfigMapValue
    configMapRef:
      name: aws-account-mycompany-dev
      namespace: crossplane-system
      key: ASSUME_ROLE_ARN
```

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
- Account aliases must be globally unique across all AWS
- The OrganizationAccountAccessRole is created automatically by AWS Organizations
- ConfigMaps are created in the management cluster only