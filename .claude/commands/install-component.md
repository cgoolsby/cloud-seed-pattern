# Install Component Command - Step-by-Step Component Installation

## Pre-Installation Checklist
Before installing any component, verify:
- [ ] Component exists in `components/helmrelease/` or needs to be created
- [ ] IRSA roles are configured if AWS access is needed
- [ ] Dependencies are already installed (e.g., cert-manager for webhooks)
- [ ] Target namespace considerations

## Installation Steps

### Step 1: Check if Component Exists
```bash
# List available components
ls -la components/helmrelease/

# If component exists, check its configuration
cat components/helmrelease/<component-name>/helmrelease.yaml
```

### Step 2: Create Component Definition (if needed)
If the component doesn't exist in `components/helmrelease/`:

```bash
# Create component directory
mkdir -p components/helmrelease/<component-name>

# Create files:
# 1. namespace.yaml (if dedicated namespace needed)
# 2. helmrepository.yaml (if new Helm repo)
# 3. helmrelease.yaml (Helm release configuration)
# 4. kustomization.yaml (to bundle resources)
```

### Step 3: Add IRSA Support (if needed)
If the component needs AWS access:

1. Add IAM role in `components/tf_initialSeedCluster/`
2. Export role ARN in `k8s-outputs.tf`
3. Reference in HelmRelease:
```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "${COMPONENT_ROLE_ARN}"
```

### Step 4: Create Cluster Integration
```bash
# Create directory for cluster-specific config
mkdir -p clusters/management/primary/<component-name>

# Create kustomization.yaml
cat > clusters/management/primary/<component-name>/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../../components/helmrelease/<component-name>
EOF
```

### Step 5: Create Flux Kustomization
```bash
# Create Flux Kustomization resource
cat > clusters/management/primary/<component-name>.yaml << EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <component-name>
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./clusters/management/primary/<component-name>
  prune: true
  timeout: 5m
  # Add if using variables from Terraform
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: terraform-outputs
  # Add dependencies if needed
  dependsOn:
    - name: cert-manager  # Example
EOF
```

### Step 6: Update Cluster Kustomization
```bash
# Edit clusters/management/primary/kustomization.yaml
# Add the new component YAML to resources list:
# - <component-name>.yaml
```

### Step 7: Test Locally (Optional)
```bash
# Use dev workflow for testing
./scripts/dev-workflow.sh start "testing <component-name> installation"

# Apply and test
kubectl apply -k clusters/management/primary/<component-name>/

# Check status
kubectl get pods -n <component-namespace>

# If satisfied, finish
./scripts/dev-workflow.sh finish "Add <component-name> component"
```

### Step 8: Commit and Deploy
```bash
# Add all files
git add components/helmrelease/<component-name>/ \
        clusters/management/primary/<component-name>/ \
        clusters/management/primary/<component-name>.yaml \
        clusters/management/primary/kustomization.yaml

# Commit
git commit -m "Add <component-name> to management cluster"

# Push
git push

# Monitor deployment
flux get kustomization <component-name> --watch
kubectl get pods -n <component-namespace> --watch
```

## Component-Specific Examples

### Example: Installing Prometheus Operator
```bash
# Component already exists in components/helmrelease/monitoring/
# Just need to add to cluster:

# 1. It's already referenced in clusters/management/primary/monitoring.yaml
# 2. It's already in clusters/management/primary/kustomization.yaml
# 3. Just ensure it's deployed:
flux get kustomization monitoring -n flux-system
```

### Example: Installing ArgoCD
```bash
# Would need to create new component:
mkdir -p components/helmrelease/argocd

# Create namespace.yaml, helmrepository.yaml, helmrelease.yaml, kustomization.yaml
# Follow steps 4-8 above
```

## Verification Commands
```bash
# Check Flux Kustomization
flux get kustomization <component-name>

# Check Helm release
kubectl get helmrelease -A | grep <component-name>

# Check pods
kubectl get pods -n <namespace>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# View logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=<component-name>
```

## Rollback if Needed
```bash
# Option 1: Suspend via Flux
flux suspend kustomization <component-name>

# Option 2: Git revert
git revert HEAD
git push

# Option 3: Remove component
# Remove from clusters/management/primary/kustomization.yaml
# Delete component files
# Commit and push
```

## Common Components Reference

| Component | Namespace | Dependencies | IRSA Needed |
|-----------|-----------|--------------|-------------|
| cert-manager | cert-manager | None | No |
| external-secrets | external-secrets | None | Yes |
| aws-load-balancer-controller | kube-system | cert-manager | Yes |
| aws-ebs-csi-driver | kube-system | None | Yes |
| crossplane | crossplane-system | None | Yes |
| cluster-api | capa-system | cert-manager | Yes |
| monitoring | monitoring | None | No |
| logging | logging | None | No |
| supabase | supabase | external-secrets | No |