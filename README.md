# k8sHyperscalar

A comprehensive Kubernetes Infrastructure-as-Code (IaC) platform for managing multi-cluster, multi-account AWS deployments using GitOps principles.

## Features

- **Multi-Account AWS Management**: Automated AWS account creation via Organizations
- **GitOps Workflow**: Flux CD for continuous deployment and reconciliation
- **Infrastructure Provisioning**: Crossplane for declarative cloud resource management
- **IRSA Authentication**: Secure, credential-free AWS access using IAM Roles for Service Accounts
- **Cluster Management**: Cluster API for Kubernetes cluster lifecycle management
- **Environment Isolation**: Separate AWS accounts for dev/staging/production environments

## Quick Start

### 1. Bootstrap Management Cluster

```bash
# Create EKS management cluster with IRSA
cd terraform/eks
terraform init
terraform apply

# Configure kubectl
aws eks update-kubeconfig --name fullStack-cluster --region us-east-1

# Bootstrap Flux GitOps
./scripts/bootstrap-flux.sh -t <github-token>
```

### 2. Create AWS Accounts (Optional)

```bash
# Set up multi-account environment
cd terraform/accounts
terraform init
cp accounts.example.tfvars accounts.tfvars
# Edit accounts.tfvars with your account details

terraform apply -var-file="accounts.tfvars"
```

### 3. Deploy Infrastructure

```bash
# Flux automatically deploys from kubernetes/ directory
# Monitor deployment
flux get all -A
kubectl get managed -A
```

## Architecture

### Repository Structure

```
k8sHyperscalar/
├── terraform/
│   ├── eks/                    # Management EKS cluster with IRSA
│   └── accounts/               # Multi-account setup via Organizations
├── kubernetes/
│   ├── base/                   # Core platform components
│   │   ├── flux-system/        # Flux CD configuration
│   │   ├── crossplane/         # Crossplane providers and compositions
│   │   ├── cluster-api/        # Cluster API controllers
│   │   ├── monitoring/         # Prometheus stack
│   │   └── logging/            # ELK stack
│   └── environments/           # Complete environments by account
│       ├── _template/          # Template for new environments
│       └── <account-name>/     # All resources for one account
│           ├── account/        # Namespace, IAM, provider config
│           ├── networking/     # VPC and network resources
│           ├── clusters/       # EKS clusters for this account
│           └── services/       # Account-specific services
└── scripts/                    # Automation scripts
```

### Key Technologies

- **EKS**: Amazon Elastic Kubernetes Service for the management cluster
- **Flux CD**: GitOps continuous delivery for Kubernetes
- **Crossplane**: Universal control plane for cloud infrastructure
- **Cluster API**: Kubernetes cluster lifecycle management
- **AWS Organizations**: Multi-account management and billing
- **IRSA**: IAM Roles for Service Accounts for secure AWS access

## Multi-Account Strategy

The platform supports environment isolation through separate AWS accounts:

1. **Account Creation**: Terraform automatically creates AWS accounts via Organizations
2. **ConfigMap Generation**: Each account gets a ConfigMap with credentials and metadata
3. **Cross-Account Access**: Crossplane uses OrganizationAccountAccessRole for resource provisioning
4. **Environment Targeting**: Resources specify target accounts using friendly aliases

Example account targeting:
```yaml
apiVersion: network.example.org/v1alpha1
kind: VPC
metadata:
  name: production-vpc
spec:
  accountName: prod-account  # References specific AWS account
  region: us-east-1
  cidrBlock: "10.0.0.0/16"
```

## Security

- **No Static Credentials**: All AWS access uses IRSA and temporary tokens
- **Least Privilege**: IAM roles follow principle of least privilege
- **Account Isolation**: Workloads are isolated in separate AWS accounts
- **GitOps Audit Trail**: All changes tracked via Git commits
- **Encryption**: EKS encryption at rest and in transit

## Getting Help

- **Commands**: See [CLAUDE.md](./CLAUDE.md) for common operations
- **Kubernetes Resources**: See [kubernetes/README.md](./kubernetes/README.md)
- **Account Management**: See [terraform/accounts/README.md](./terraform/accounts/README.md)
- **Troubleshooting**: Check CLAUDE.md troubleshooting section

## Development Workflow

### Creating a New Environment
1. **Create AWS Account**: Use `terraform/accounts/` to create account
2. **Setup Environment**: Run `./scripts/gitops-account-setup.sh <account-alias>`
3. **Commit & Push**: Git commit the new environment configuration
4. **Monitor**: Use `flux events --watch` to monitor deployment

### Cluster Management (GitOps)
All cluster operations should go through pull requests for proper review and audit:

1. **Create Cluster**: 
   ```bash
   ./scripts/gitops-create-cluster.sh <account-alias> <cluster-name> [namespace]
   git push origin <branch-name>
   gh pr create --title "Add EKS cluster: <cluster-name>"
   ```

2. **Destroy Cluster**: 
   ```bash
   ./scripts/gitops-destroy-cluster.sh <account-alias> <cluster-name>
   git push origin <branch-name>
   gh pr create --title "Remove EKS cluster: <cluster-name>"
   ```

3. **Monitor Deployment**:
   ```bash
   flux get kustomization -n aws-<account-alias> <cluster-name>
   kubectl get cluster -A | grep <cluster-name>
   ```

### Standard Workflow
1. **Make Changes**: Edit manifests in the appropriate environment directory
2. **Create PR**: Push changes to a feature branch and create PR
3. **Review**: Team reviews infrastructure changes
4. **Merge**: After approval, merge to main branch
5. **Flux Sync**: Flux automatically applies changes to cluster
6. **Validate**: Check resource status with kubectl/Crossplane commands

This platform enables teams to manage complex, multi-environment Kubernetes infrastructure using cloud-native, GitOps best practices.