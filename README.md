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
│   ├── clusters/               # Cluster definitions by environment
│   └── infrastructure/         # Cloud resources via Crossplane
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

1. **Make Changes**: Edit Kubernetes manifests or Terraform code
2. **Commit & Push**: Changes are tracked via Git
3. **Flux Sync**: Flux automatically applies changes to cluster
4. **Monitor**: Use `flux events --watch` to monitor reconciliation
5. **Validate**: Check resource status with kubectl/Crossplane commands

This platform enables teams to manage complex, multi-environment Kubernetes infrastructure using cloud-native, GitOps best practices.