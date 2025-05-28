# Cluster Templates with Flux Variable Substitution

This directory contains reusable cluster templates that use Flux's variable substitution feature to eliminate boilerplate code.

## How It Works

1. **Base Template** (`eks-cluster.yaml`): Contains the full cluster definition with variables like `${CLUSTER_NAME}`, `${VPC_ID}`, etc.

2. **Environment Values** (`environments/<account>/cluster-values.yaml`): ConfigMap with environment-specific values (VPC ID, subnet IDs, etc.)

3. **Cluster Values** (`environments/<account>/clusters/<name>/kustomization.yaml`): Cluster-specific overrides (name, size, etc.)

4. **Flux Substitution**: Flux replaces variables when deploying the cluster

## Benefits

- **No Duplication**: One template serves all clusters
- **Easy Updates**: Change template once, affects all clusters
- **Simple Clusters**: New clusters need only 10-15 lines of config
- **Dynamic Values**: Automatically pull VPC/subnet IDs from live resources

## Creating a New Cluster

### 1. Update Environment Values (if needed)
```bash
# Automatically extract values from deployed resources
./scripts/update-cluster-values.sh <account-alias>

# Apply the ConfigMap
kubectl apply -f kubernetes/environments/<account>/cluster-values.yaml
```

### 2. Create Cluster Directory
```bash
mkdir -p kubernetes/environments/<account>/clusters/<cluster-name>
```

### 3. Create Cluster Configuration
```yaml
# kubernetes/environments/<account>/clusters/<cluster-name>/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../../base/cluster-templates/eks-cluster.yaml

configMapGenerator:
  - name: <cluster-name>-values
    namespace: flux-system
    literals:
      - CLUSTER_NAME=<cluster-name>
      - CLUSTER_NAMESPACE=default
      # Optional overrides
      - NODE_INSTANCE_TYPE=t3.large  # Override default t3.medium
      - NODE_DESIRED_SIZE=5           # Override default 2
```

### 4. Create Flux Kustomization
```yaml
# kubernetes/environments/<account>/clusters/<cluster-name>/flux-kustomization.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster-<cluster-name>-<account>
  namespace: flux-system
spec:
  interval: 5m0s
  path: ./kubernetes/environments/<account>/clusters/<cluster-name>
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: env-<account>
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: cluster-values        # Environment values
      - kind: ConfigMap
        name: <cluster-name>-values # Cluster-specific values
  wait: false
  timeout: 60m0s
```

### 5. Deploy
```bash
# Commit and push
git add kubernetes/environments/<account>/clusters/<cluster-name>
git commit -m "Add <cluster-name> cluster"
git push

# Or apply directly
kubectl apply -f kubernetes/environments/<account>/clusters/<cluster-name>/flux-kustomization.yaml
```

## Variables Reference

### Environment Variables (from cluster-values ConfigMap)
- `${ACCOUNT_ALIAS}` - AWS account alias
- `${ACCOUNT_ID}` - AWS account ID
- `${ENVIRONMENT}` - Environment name (development/staging/production)
- `${VPC_ID}` - VPC ID
- `${REGION}` - AWS region
- `${PRIVATE_SUBNET_A/B/C}` - Private subnet IDs
- `${PUBLIC_SUBNET_A/B/C}` - Public subnet IDs
- `${EKS_VERSION}` - Default EKS version
- `${NODE_INSTANCE_TYPE}` - Default instance type
- `${NODE_MIN_SIZE}` - Default min nodes
- `${NODE_MAX_SIZE}` - Default max nodes
- `${NODE_DESIRED_SIZE}` - Default desired nodes
- `${VPC_CNI_VERSION}` - VPC CNI addon version
- `${COREDNS_VERSION}` - CoreDNS addon version
- `${KUBE_PROXY_VERSION}` - kube-proxy addon version

### Cluster Variables (from cluster-specific ConfigMap)
- `${CLUSTER_NAME}` - Cluster name (required)
- `${CLUSTER_NAMESPACE}` - Namespace for cluster resources (default: "default")
- Any environment variable can be overridden

## Examples

### Minimal Cluster (uses all defaults)
```yaml
configMapGenerator:
  - name: minimal-cluster-values
    namespace: flux-system
    literals:
      - CLUSTER_NAME=minimal-cluster
```

### Production Cluster (with overrides)
```yaml
configMapGenerator:
  - name: prod-cluster-values
    namespace: flux-system
    literals:
      - CLUSTER_NAME=prod-cluster
      - NODE_INSTANCE_TYPE=m5.xlarge
      - NODE_MIN_SIZE=3
      - NODE_MAX_SIZE=20
      - NODE_DESIRED_SIZE=5
      - EKS_VERSION=v1.29  # Use newer version
```

### Multi-AZ Cluster (selective AZs)
```yaml
configMapGenerator:
  - name: two-az-cluster-values
    namespace: flux-system
    literals:
      - CLUSTER_NAME=two-az-cluster
      # Override to use only 2 AZs
      - PRIVATE_SUBNET_C=""  # Empty string removes from list
```

## Comparison: Before and After

### Before (150+ lines per cluster)
Each cluster needed a complete copy of all resources with hardcoded values.

### After (10-15 lines per cluster)
Each cluster only specifies its name and any overrides.

## Maintenance

### Updating Add-on Versions
Edit the cluster-values ConfigMap to update versions across all clusters:
```bash
# Update the ConfigMap
kubectl edit configmap cluster-values -n flux-system

# Or regenerate from current resources
./scripts/update-cluster-values.sh <account-alias>
```

### Adding New Variables
1. Add to the template (`eks-cluster.yaml`)
2. Add default to environment ConfigMap
3. Document in this README

### Template Changes
Changes to `eks-cluster.yaml` automatically apply to all clusters on next reconciliation.