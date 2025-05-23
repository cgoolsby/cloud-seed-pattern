# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Kubernetes Infrastructure-as-Code (IaC) repository for managing multi-cluster Kubernetes deployments on AWS using GitOps principles. It combines Terraform for bootstrapping, Flux CD for GitOps, Crossplane for cloud infrastructure provisioning, and Cluster API for Kubernetes cluster lifecycle management.

## Key Commands

### Initial Setup
```bash
# Bootstrap management EKS cluster
cd terraform/eks
terraform init
terraform apply

# Configure kubectl for the management cluster
aws eks update-kubeconfig --name fullStack-cluster --region us-east-1

# Bootstrap Flux (requires GitHub token with repo permissions)
./scripts/bootstrap-flux.sh -t <github-token>

# Check Flux health
flux check
flux get all -A
```

### Development Workflow
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

# Check Cluster API resources
kubectl get clusters -A
kubectl get machinedeployments -A
```

## Architecture

### Directory Structure
- **terraform/eks/**: Terraform code for bootstrapping the management EKS cluster
- **kubernetes/base/**: Core platform components (Flux, Crossplane, Cluster API)
- **kubernetes/clusters/**: Cluster definitions organized by environment (dev/staging/prod)
- **kubernetes/infrastructure/**: Cloud infrastructure resources managed by Crossplane

### Key Components
1. **Flux CD**: Watches this Git repository and applies changes to the cluster
2. **Crossplane**: Provisions AWS resources (VPCs, IAM roles) declaratively
3. **Cluster API**: Manages lifecycle of workload Kubernetes clusters
4. **Kustomize**: Used throughout for configuration management

### Resource Creation Pattern
When creating new clusters or infrastructure:
1. Copy from templates in `clusters/templates/` or `infrastructure/templates/`
2. Replace placeholder variables (e.g., ${CLUSTER_NAME})
3. Add the new file to the corresponding kustomization.yaml
4. Commit and push - Flux will automatically apply

### Multi-Account Support
The repository supports multi-AWS-account deployments through Crossplane provider configurations. Each account requires its own provider configuration in `kubernetes/base/crossplane/providers/`.

## Important Notes
- Default cluster name: `fullStack-cluster`
- Default region: `us-east-1`
- Flux path in repo: `kubernetes/base`
- All Kubernetes resources are managed declaratively - avoid kubectl apply directly
- Monitor reconciliation status with `flux events --watch` when making changes