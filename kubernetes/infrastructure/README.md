# Infrastructure Directory

## ⚠️ Important Notice

Most infrastructure resources should be created through the **accounts** structure:
- `kubernetes/accounts/overlays/<account-name>/`

The accounts workflow provides:
- Proper namespace isolation (`aws-<account-name>`)
- Consistent CIDR allocation
- Integration with CAPA IAM roles
- GitOps-friendly structure

## Directory Purpose

This directory is reserved for:
1. **Cross-account resources** that don't belong to a specific account
2. **Shared infrastructure** used by multiple accounts
3. **Test resources** for Crossplane composition development (use sparingly)

## Current Structure

```
infrastructure/
├── aws/                    # AWS-specific resources
│   └── vpc/               # VPC resources (mostly deprecated)
├── templates/             # Resource templates (reference only)
└── kustomization.yaml     # Kustomize configuration
```

## Best Practices

1. **Always prefer the accounts structure** for account-specific resources
2. **Use proper namespaces** (aws-<account-name>) for isolation
3. **Follow CIDR allocation** strategy:
   - Production: 10.0.0.0/16
   - Staging: 10.1.0.0/16
   - Development: 10.2.0.0/16
   - Others: 10.100+.0.0/16

## Creating Resources

For new AWS accounts and their resources:
```bash
./scripts/gitops-account-setup.sh <account-alias>
```

This will create all necessary resources in the correct structure.