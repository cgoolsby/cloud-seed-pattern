# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Kubernetes Infrastructure-as-Code (IaC) repository for managing multi-cluster, multi-account Kubernetes deployments on AWS using GitOps principles. It combines Terraform for bootstrapping, Flux CD for GitOps, Crossplane for cloud infrastructure provisioning, and Cluster API for Kubernetes cluster lifecycle management.

## Key Commands

### Initial Setup
```bash
# 1. Bootstrap management EKS cluster with IRSA
cd components/tf_initialSeedCluster
terraform init
terraform apply

# 2. Configure kubectl for the management cluster
aws eks update-kubeconfig --name fullStack-cluster --region us-east-1

# 3. Bootstrap Flux (requires GitHub token with repo permissions)
./scripts/bootstrap-flux.sh -t <github-token>

# 4. Check Flux health and Crossplane deployment
flux check
flux get all -A
kubectl get pods -n crossplane-system
```

### Multi-Account Setup
```bash
# Create additional AWS accounts for environments
cd components/tf_accounts
terraform init
cp accounts.example.tfvars accounts.tfvars
# Edit accounts.tfvars with your account details

# First time: create organization (if needed) and accounts
terraform apply -var="create_organization=true" -var-file="accounts.tfvars"

# Subsequent runs: add new accounts
terraform apply -var-file="accounts.tfvars"

# Verify ConfigMaps were created
kubectl get configmaps -n crossplane-system | grep aws-account
```

### Development Workflow

#### Preferred Local Development Workflow
When debugging or developing new resources, use the local development workflow to avoid cluttering git history with debug commits:

```bash
# Start a development session
./scripts/dev-workflow.sh start "debugging VPC composition"

# Test your changes locally without committing
./scripts/dev-workflow.sh test kubernetes/infrastructure/aws/vpc/test-vpc.yaml

# Preview what would change
./scripts/dev-workflow.sh diff kubernetes/infrastructure/aws/vpc/test-vpc.yaml

# Create checkpoints as you work (local commits)
./scripts/dev-workflow.sh checkpoint "fixed route table issue"

# When everything works, package into a single commit
./scripts/dev-workflow.sh finish "Fix VPC composition RouteTable associations"

# Check session status anytime
./scripts/dev-workflow.sh status
```

This workflow:
- Pauses Flux reconciliation automatically
- Creates a temporary work branch for your experiments
- Allows fast iteration with `kubectl apply` directly
- Tracks your work with checkpoint commits
- Squashes everything into a clean final commit
- Resumes Flux when you're done

#### Production Workflow
For deploying changes across environments:

```bash
# Update Flux to track a different branch
./scripts/update-flux-branch.sh <branch-name>

# Force reconciliation of Flux resources
flux reconcile source git flux-system
flux reconcile kustomization flux-system

# Monitor Flux events
flux events --watch

# Check Crossplane resource status
kubectl get managed -A
kubectl get composite -A
kubectl get vpcs.network.example.org -A

# Check multi-account ProviderConfigs
kubectl get providerconfigs.aws.crossplane.io -A

# Check Cluster API resources
kubectl get clusters -A
kubectl get machinedeployments -A
```

### Code Quality Tools

#### Pre-commit Setup
This repository uses pre-commit hooks to ensure code quality and catch issues before committing:

```bash
# Install pre-commit (requires Python)
pip install pre-commit

# Install the git hooks
pre-commit install

# Run manually on all files (useful for initial setup)
pre-commit run --all-files

# Update hook versions
pre-commit autoupdate
```

The pre-commit configuration includes:
- **YAML validation**: Syntax checking and formatting with yamllint
- **Kubernetes validation**: Manifest validation with kubeval
- **Shell scripts**: Linting with shellcheck
- **Terraform**: Format checking and validation with terraform fmt/validate and tflint
- **Security**: Secret detection to prevent accidental commits
- **General**: Trailing whitespace, large files, merge conflicts

To skip hooks temporarily (not recommended):
```bash
git commit --no-verify -m "emergency fix"
```

To run specific hooks:
```bash
# Run only YAML linting
pre-commit run yamllint --all-files

# Run only on staged files (default behavior)
pre-commit run
```

## Architecture

### Directory Structure
- **components/**: Reusable modules and base configurations
  - **tf_initialSeedCluster/**: Terraform for bootstrapping management EKS cluster with IRSA
  - **tf_accounts/**: Terraform module for creating AWS accounts and ConfigMaps
  - **helmrelease/**: Helm-based deployments (EBS CSI, cert-manager, monitoring, logging)
  - **kustomizations/**: Reusable Kustomize bases for accounts, clusters, networking
- **clusters/**: Complete cluster configurations
  - **_template/**: Template structure for new clusters
  - **management/**: Management cluster configuration
  - **<account-name>/**: Workload cluster configurations
- **scripts/**: Automation scripts for common operations

### Key Components
1. **Flux CD**: Watches this Git repository and applies changes to the cluster
2. **Crossplane**: Provisions AWS resources using IRSA authentication and cross-account assume roles
3. **Cluster API**: Manages lifecycle of workload Kubernetes clusters
4. **AWS Organizations**: Manages multiple AWS accounts for environment isolation
5. **Kustomize**: Used throughout for configuration management

### Multi-Account Workflow
1. **Create Account**: Add to `components/tf_accounts/accounts.tfvars` and run `terraform apply`
2. **Auto-Generated ConfigMaps**: Terraform creates ConfigMaps with account details in crossplane-system namespace
3. **ProviderConfig**: Reference ConfigMaps to create ProviderConfigs for cross-account access
4. **Resource Provisioning**: Use account alias in Crossplane resources (e.g., `accountName: dev-account`)

### Resource Creation Pattern
When creating new environments or clusters:
1. Use `./scripts/gitops-account-setup.sh <account-alias>` to create a new environment
2. For clusters, use `./scripts/gitops-create-cluster.sh <account-alias> <cluster-name>`
3. Templates are in `clusters/_template/`
4. All resources for an account are grouped in `clusters/<account-name>/`
5. Commit and push - Flux will automatically apply

### IRSA Authentication Setup
- **Management Account**: Uses IRSA with CrossplaneAWSProviderRole
- **Target Accounts**: Uses OrganizationAccountAccessRole for cross-account access
- **Wildcard Trust Policy**: Handles dynamic Crossplane service account names (provider-aws-*)
- **No Static Credentials**: All authentication uses temporary tokens via IRSA

### Environment and Cluster Management

#### GitOps Workflow (Recommended)
All cluster operations should go through pull requests for proper review and audit trail:

```bash
# Create a new environment (account + networking)
./scripts/gitops-account-setup.sh <account-alias>

# Create a cluster via GitOps (generates PR)
./scripts/gitops-create-cluster.sh <account-alias> <cluster-name> [namespace]

# Destroy a cluster via GitOps (generates PR)
./scripts/gitops-destroy-cluster.sh <account-alias> <cluster-name>

# Check environment status
kubectl get all -n aws-<account-alias>
kubectl get vpc,subnets -n aws-<account-alias>

# Monitor cluster deployment after PR merge
flux get kustomization -n aws-<account-alias> <cluster-name>
kubectl get cluster -A | grep <cluster-name>
```

The GitOps workflow:
1. **Create**: Generates cluster manifests and creates a PR branch
2. **Review**: Team reviews the changes in the PR
3. **Deploy**: After merge, Flux automatically creates the cluster
4. **Monitor**: Use Flux commands to track deployment progress
5. **Destroy**: Similar process but removes the cluster configuration

#### Direct Apply Workflow (Development Only)
For development and testing only - avoid in production:

```bash
# Create a cluster directly (bypasses GitOps)
./scripts/create-cluster.sh <account-alias> <cluster-name>

# Destroy a cluster directly
./scripts/destroy-cluster.sh <cluster-name>
```

## Troubleshooting

### Crossplane IRSA Issues
```bash
# Check provider pod status and logs
kubectl get pods -n crossplane-system | grep provider-aws
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws --tail=50

# Verify service account annotations
kubectl get sa -n crossplane-system | grep provider-aws
kubectl describe sa provider-aws-controller -n crossplane-system

# Check ProviderConfig status
kubectl describe providerconfig default -n crossplane-system
```

### VPC Composition Issues
- **Route Table Error**: The VPC composition has a known issue with RouteTable associations
- **Account Access**: Verify OrganizationAccountAccessRole exists in target account
- **AZ Assumptions**: VPC composition assumes regions have 'a' and 'b' availability zones

## Important Notes
- Default cluster name: `fullStack-cluster`
- Default region: `us-east-1`
- Flux monitors the entire repository except for Terraform directories
- All Kubernetes resources are managed declaratively - avoid kubectl apply directly
- Monitor reconciliation status with `flux events --watch` when making changes
- Account deletion via Terraform requires manual steps due to AWS Organizations constraints
- To enable pre-commit hooks, rename `.pre-commit-config.yaml.bak` to `.pre-commit-config.yaml`