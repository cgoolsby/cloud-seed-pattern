# Missing Scripts TODO

This document tracks scripts referenced in CLAUDE.md that don't exist yet, along with their expected functionality.

## High Priority Scripts

### 1. gitops-account-setup.sh
**Purpose**: Create a new AWS account and set up GitOps structure via PR

**Expected functionality**:
```bash
./scripts/gitops-account-setup.sh <account-alias>
```

**Should**:
- Create a new branch `feature/add-<account-alias>-environment`
- Generate directory structure under `clusters/<account-alias>/`
- Create base kustomization files
- Create namespace configuration
- Create ProviderConfig for Crossplane
- Generate PR with all changes

**Template structure needed**:
```
clusters/<account-alias>/
├── kustomization.yaml
├── namespace.yaml
├── provider-config.yaml
└── networking/
    └── vpc.yaml
```

### 2. gitops-create-cluster.sh
**Purpose**: Generate cluster manifests and create PR for new cluster

**Expected functionality**:
```bash
./scripts/gitops-create-cluster.sh <account-alias> <cluster-name> [namespace]
```

**Should**:
- Create branch `feature/add-<cluster-name>-cluster`
- Use templates from `clusters/_template/`
- Substitute variables (account, cluster name, namespace)
- Create PR with cluster configuration
- Support both management and workload clusters

### 3. gitops-destroy-cluster.sh
**Purpose**: Remove cluster configuration via PR

**Expected functionality**:
```bash
./scripts/gitops-destroy-cluster.sh <account-alias> <cluster-name>
```

**Should**:
- Create branch `feature/remove-<cluster-name>-cluster`
- Remove cluster directory and references
- Update parent kustomization.yaml
- Create PR for review
- Include safety checks

### 4. update-flux-branch.sh
**Purpose**: Update Flux to track a different Git branch

**Expected functionality**:
```bash
./scripts/update-flux-branch.sh <branch-name>
```

**Should**:
- Update GitRepository resource to track new branch
- Force reconciliation
- Verify branch exists in remote
- Show before/after configuration

### 5. collect-diagnostics.sh
**Purpose**: Collect system diagnostics for troubleshooting

**Expected functionality**:
```bash
./scripts/collect-diagnostics.sh [output-dir]
```

**Should collect**:
- flux check output
- All pod logs from key namespaces
- Recent events
- Resource descriptions
- Git repository state
- Kubernetes version info
- Node status

## Medium Priority Scripts

### 6. destroy-cluster.sh (implementation)
**Current state**: Empty file exists

**Should implement**:
- Suspend Flux reconciliation for cluster
- Delete Cluster API resources
- Clean up AWS resources
- Remove cluster configuration
- Support --force flag

### 7. validate-environment.sh
**Purpose**: Validate environment before operations

**Should check**:
- Required tools installed (flux, kubectl, aws, git)
- AWS credentials configured
- Kubernetes context correct
- GitHub token available
- Terraform state accessible

## Low Priority Scripts

### 8. rotate-secrets.sh
**Purpose**: Rotate IRSA credentials and secrets

### 9. backup-cluster-state.sh
**Purpose**: Backup critical cluster state

### 10. promote-release.sh
**Purpose**: Promote releases between environments

## Implementation Notes

### Common Patterns
All GitOps scripts should:
1. Check for clean git state
2. Create feature branches
3. Use templates where applicable  
4. Generate descriptive PR bodies
5. Include rollback instructions
6. Validate inputs

### Error Handling
- Check prerequisites before making changes
- Provide clear error messages
- Support --dry-run flag
- Log actions for audit trail

### Integration Points
- Use existing templates in `scripts/templates/`
- Leverage `envsubst` for variable substitution
- Follow naming conventions from create-cluster.sh
- Integrate with dev-workflow.sh patterns