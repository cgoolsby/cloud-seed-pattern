# Cloud Seed Pattern Scripts

This directory contains automation scripts for managing Kubernetes clusters, components, and GitOps workflows in the cloud-seed-pattern infrastructure.

## Overview

The scripts are designed to work together to provide a complete lifecycle management solution for multi-cluster Kubernetes deployments on AWS using GitOps principles.

### Core Components

- **common.sh** - Shared library of functions used by all scripts
- **bootstrap-flux.sh** - Bootstrap Flux CD on a Kubernetes cluster
- **create-cluster.sh** - Create a new cluster configuration
- **destroy-cluster.sh** - Destroy an existing cluster
- **component-add.sh** - Add a component to a cluster
- **component-remove.sh** - Remove a component from a cluster
- **dev-workflow.sh** - Local development workflow helper

## Prerequisites

Before using these scripts, ensure you have:

1. **Required Tools**:
   - `kubectl` - Kubernetes CLI
   - `flux` - Flux CD CLI
   - `git` - Version control
   - `yq` - YAML processor (for management clusters)
   - `aws` - AWS CLI (configured)

2. **Access Requirements**:
   - Kubernetes cluster access via kubectl
   - GitHub token with repository permissions
   - AWS account access (for cluster operations)

## Quick Start

### 1. Bootstrap Flux on a Cluster

```bash
# Bootstrap Flux on a managed cluster
./scripts/bootstrap-flux.sh -a dev-account -c primary-cluster

# Bootstrap Flux on a management cluster (includes Crossplane & Cluster API)
./scripts/bootstrap-flux.sh -a management -c mgmt-cluster -m

# With custom GitHub settings
./scripts/bootstrap-flux.sh -a prod-account -c prod-cluster \
  -t $GITHUB_TOKEN \
  -o your-org \
  -r your-repo \
  -b main
```

### 2. Create a New Cluster

```bash
# Create a development cluster with defaults
./scripts/create-cluster.sh dev-account dev-cluster

# Create a production cluster with custom settings
./scripts/create-cluster.sh prod-account prod-cluster \
  -e production \
  -n 3 \
  -t t3.large \
  -r us-west-2

# Create a management cluster
./scripts/create-cluster.sh management mgmt-cluster --management
```

### 3. Add Components to a Cluster

```bash
# Add cert-manager to a cluster
./scripts/component-add.sh cert-manager dev-account dev-cluster

# Add aws-ebs-csi with custom namespace
./scripts/component-add.sh aws-ebs-csi prod-account prod-cluster -n kube-system

# Add component and wait for it to be ready
./scripts/component-add.sh external-secrets dev-account dev-cluster --wait

# Add component with custom values
./scripts/component-add.sh monitoring dev-account dev-cluster \
  -v ./custom-monitoring-values.yaml
```

### 4. Remove Components from a Cluster

```bash
# Remove a component with confirmation
./scripts/component-remove.sh cert-manager dev-account dev-cluster

# Force remove without confirmation
./scripts/component-remove.sh monitoring dev-account dev-cluster --force

# Remove and wait for cleanup
./scripts/component-remove.sh external-secrets dev-account dev-cluster --wait
```

### 5. Destroy a Cluster

```bash
# Destroy with confirmation
./scripts/destroy-cluster.sh dev-account old-cluster

# Force destroy without confirmation
./scripts/destroy-cluster.sh test-account test-cluster --force

# Destroy but keep configuration files
./scripts/destroy-cluster.sh dev-account backup-cluster --keep-config

# Destroy and wait for completion
./scripts/destroy-cluster.sh prod-account decom-cluster --wait
```

## Development Workflow

The `dev-workflow.sh` script helps you work locally with Flux-managed resources:

```bash
# Start a development session
./scripts/dev-workflow.sh start "debugging VPC composition"

# Test changes locally
./scripts/dev-workflow.sh test kubernetes/infrastructure/aws/vpc/test-vpc.yaml

# Create checkpoints as you work
./scripts/dev-workflow.sh checkpoint "fixed route table issue"

# Preview changes
./scripts/dev-workflow.sh diff kubernetes/infrastructure/aws/vpc/test-vpc.yaml

# Finish and create final commit
./scripts/dev-workflow.sh finish "Fix VPC composition RouteTable associations"

# Check session status
./scripts/dev-workflow.sh status

# Abort session if needed
./scripts/dev-workflow.sh abort
```

## Script Details

### common.sh

Provides shared functions and utilities:
- Color-coded output functions (print_error, print_success, etc.)
- Input validation functions
- Git operations helpers
- Kubernetes utilities
- Default configuration values

### bootstrap-flux.sh

Bootstraps Flux CD on a Kubernetes cluster:
- Creates cluster directory structure from templates
- Sets up account-level kustomizations
- Configures management clusters with Crossplane and Cluster API
- Handles GitHub integration and authentication

Options:
- `-a` - Account name (required)
- `-c` - Cluster name (required)
- `-m` - Bootstrap as management cluster
- `-t` - GitHub token
- `-o` - GitHub owner
- `-r` - Repository name
- `-b` - Branch name

### create-cluster.sh

Creates new cluster configurations:
- Generates cluster structure from templates
- Calculates subnet CIDRs automatically
- Supports both managed and management clusters
- Integrates with existing account structures

Options:
- `-r, --region` - AWS region (default: us-east-1)
- `-e, --environment` - Environment tag (default: dev)
- `-v, --vpc-cidr` - VPC CIDR block (default: 10.0.0.0/16)
- `-k, --k8s-version` - Kubernetes version (default: 1.28)
- `-n, --node-count` - Number of worker nodes (default: 2)
- `-t, --node-type` - EC2 instance type (default: t3.medium)
- `-m, --management` - Create as management cluster

### destroy-cluster.sh

Safely destroys clusters:
- Removes cluster from Flux management
- Optionally preserves configuration files
- Waits for resource cleanup
- Handles both Cluster API and regular clusters

Options:
- `-f, --force` - Skip confirmation prompts
- `-k, --keep-config` - Keep configuration files
- `-w, --wait` - Wait for destruction to complete
- `-t, --timeout` - Timeout for waiting (default: 600s)

### component-add.sh

Adds components to clusters:
- Supports all components in components/helmrelease/
- Handles custom values files
- Manages component dependencies
- Supports variable substitution for IRSA roles

Options:
- `-n, --namespace` - Override default namespace
- `-v, --values` - Custom values file path
- `-p, --priority` - Reconciliation priority
- `-w, --wait` - Wait for component to be ready
- `-t, --timeout` - Wait timeout (default: 300s)

### component-remove.sh

Removes components from clusters:
- Safely removes component configurations
- Cleans up custom values
- Waits for resource cleanup
- Updates kustomizations automatically

Options:
- `-f, --force` - Skip confirmation
- `-w, --wait` - Wait for removal
- `-t, --timeout` - Wait timeout (default: 300s)

## Available Components

The following components can be added to clusters:
- aws-ebs-csi - AWS EBS CSI driver
- aws-efs-csi - AWS EFS CSI driver
- aws-load-balancer-controller - AWS Load Balancer Controller
- cert-manager - Certificate management
- cluster-api - Cluster API (management clusters)
- crossplane - Crossplane (management clusters)
- external-secrets - External Secrets Operator
- flux-system - Flux CD components
- logging - Elasticsearch, Fluent Bit, Kibana
- monitoring - Prometheus stack

## Best Practices

1. **Always commit and push changes** - The scripts automatically commit changes, but ensure your local repository is up to date

2. **Use meaningful names** - Follow the naming convention: `<environment>-<purpose>` (e.g., dev-cluster, prod-api)

3. **Test in development first** - Always test cluster and component changes in a development environment

4. **Monitor Flux reconciliation** - After making changes, monitor Flux:
   ```bash
   flux get kustomizations -A
   flux events --watch
   ```

5. **Check component status** - After adding components:
   ```bash
   kubectl get all -n <namespace> -l app.kubernetes.io/name=<component>
   ```

## Troubleshooting

### Common Issues

1. **kubectl not configured**
   ```bash
   # Update kubeconfig for EKS
   aws eks update-kubeconfig --name <cluster-name> --region <region>
   ```

2. **GitHub token issues**
   ```bash
   # Set GitHub token
   export GITHUB_TOKEN=$(gh auth token)
   ```

3. **Component not found**
   ```bash
   # List available components
   ls -1 components/helmrelease/*.yaml | xargs -n1 basename | sed 's/.yaml//'
   ```

4. **Flux reconciliation stuck**
   ```bash
   # Force reconciliation
   flux reconcile kustomization flux-system
   ```

### Debug Mode

Enable debug output for scripts:
```bash
export DEBUG=true
./scripts/create-cluster.sh dev-account debug-cluster
```

## Contributing

When adding new scripts:
1. Source `common.sh` for shared functions
2. Follow the existing naming conventions
3. Include comprehensive help/usage information
4. Add error handling and validation
5. Update this README with usage examples

## Future Enhancements

Planned improvements:
- GitOps-based cluster creation workflow
- Automated testing for components
- Backup and restore functionality
- Multi-region cluster support
- Cost estimation integration