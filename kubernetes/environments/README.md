# Kubernetes Environments

This directory contains complete environment configurations, organized by AWS account. Each environment includes all resources needed for that account: namespace, IAM roles, networking, clusters, and services.

## Directory Structure

```
environments/
├── _template/              # Template for new environments
│   ├── account/           # Account setup (namespace, IAM, provider)
│   ├── networking/        # VPC and network resources
│   ├── clusters/          # Cluster configurations
│   └── services/          # Account-specific services
└── <account-name>/        # Actual environment (e.g., test-account-1)
    ├── account/           # Account resources
    ├── networking/        # VPC configuration
    ├── clusters/          # EKS clusters
    └── kustomization.yaml # Ties everything together
```

## Creating a New Environment

Use the automation script:
```bash
./scripts/gitops-account-setup.sh <account-alias>
```

This will:
1. Create the environment directory structure
2. Generate all necessary configurations
3. Set up proper CIDR allocation based on environment type
4. Create Flux kustomizations for GitOps

## Environment Organization

Each environment follows a hierarchical structure:

1. **Account** - Base resources
   - Namespace with proper labels
   - AWS account information ConfigMap
   - Crossplane ProviderConfig for cross-account access
   - CAPA IAM roles for cluster management
   - Cluster role identity for CAPA

2. **Networking** - Network foundation
   - VPC with environment-specific CIDR
   - Public and private subnets across AZs
   - Internet gateway and NAT gateway
   - Route tables and associations

3. **Clusters** - EKS clusters
   - Each cluster in its own subdirectory
   - Cluster, control plane, and node pool definitions
   - References VPC and subnets from networking layer

4. **Services** - Account-specific services
   - Databases, caches, queues
   - Any AWS services specific to this account

## CIDR Allocation

Default CIDR allocation by environment:
- Production: `10.0.0.0/16`
- Staging: `10.1.0.0/16`
- Development: `10.2.0.0/16`
- Others: `10.100+.0.0/16`

Subnet allocation within each VPC:
- Public: `10.X.0.0/24`, `10.X.1.0/24`, `10.X.2.0/24`
- Private: `10.X.100.0/24`, `10.X.101.0/24`, `10.X.102.0/24`

## Flux Integration

Each environment has two Flux kustomizations:
1. **Base environment** - Account and networking resources
2. **Clusters** - Deployed after networking is ready

This ensures proper dependency ordering during deployment.

## Best Practices

1. **One directory per AWS account** - All resources for an account in one place
2. **Use the template** - Always start from `_template/` for consistency
3. **Follow naming conventions** - Use kebab-case for account names
4. **Commit atomically** - Commit all files for a new environment together
5. **Let Flux deploy** - Don't use `kubectl apply` directly

## Troubleshooting

Check environment status:
```bash
# Check namespace and basic resources
kubectl get all -n aws-<account-alias>

# Check VPC and networking
kubectl get vpc,subnets,routetables -n aws-<account-alias>

# Check cluster status
kubectl get clusters -A -l account.aws/alias=<account-alias>

# Check Flux kustomization
flux get kustomization env-<account-alias>
```