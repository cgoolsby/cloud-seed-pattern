# AWS Account Management via GitOps

This directory contains the GitOps configuration for managing AWS accounts, their resources, and clusters.

## Directory Structure

```
accounts/
├── README.md                 # This file
├── base/                     # Base configurations
│   ├── namespace/           # Namespace template
│   ├── iam/                 # CAPA IAM roles template
│   ├── networking/          # VPC template
│   └── kustomization.yaml   
└── overlays/                # Per-account configurations
    ├── test-account-1/      # Example account
    │   ├── account-info.yaml
    │   ├── iam-roles.yaml
    │   ├── vpc.yaml
    │   └── kustomization.yaml
    └── demo-prod/           # Another account example
        └── ...

```

## Adding a New Account

1. First, create the AWS account using Terraform:
   ```bash
   cd terraform/accounts
   # Edit accounts.tfvars to add the new account
   terraform plan -var-file=accounts.tfvars
   terraform apply -var-file=accounts.tfvars
   ```

2. Create a new overlay directory:
   ```bash
   cd kubernetes/accounts/overlays
   cp -r _template new-account-name
   ```

3. Edit the files in the new directory:
   - Update account-specific values
   - Commit and push
   - Flux will automatically create all resources

## Resources Created Per Account

- Dedicated namespace (`aws-<account-alias>`)
- Crossplane ProviderConfig
- CAPA IAM roles (via Crossplane composition)
- VPC with subnets (via Crossplane composition)
- CAPA cluster role identity

## Creating Clusters

Clusters are managed in the `kubernetes/clusters/` directory, organized by account.