# Test Account 1 Environment

This environment contains all resources for the test-account-1 AWS account.

## Setup Workflow

### 1. Initial Deployment
```bash
# Apply via GitOps
git add kubernetes/environments/test-account-1
git commit -m "Add test-account-1 environment"
git push

# Or apply directly during development
kubectl apply -k kubernetes/environments/test-account-1/account/
kubectl apply -k kubernetes/environments/test-account-1/networking/
```

### 2. Wait for Networking
```bash
# Wait for VPC to be ready
kubectl wait --for=condition=Ready vpc.network.example.org/main \
  -n aws-test-account-1 --timeout=10m

# Verify subnets are created
kubectl get subnets -A -l crossplane.io/claim-namespace=aws-test-account-1
```

### 3. Update Cluster Values
Once networking is ready, capture the dynamic values:

```bash
# This updates both the live ConfigMap and the file
./scripts/update-cluster-values.sh test-account-1

# Commit the generated values
git add kubernetes/environments/test-account-1/cluster-values.yaml
git commit -m "Update cluster values for test-account-1"
git push
```

### 4. Create Clusters
Now you can create clusters using the simplified pattern:

```bash
# Create a development cluster
./scripts/create-cluster-flux.sh test-account-1 dev-cluster

# Create a production cluster with overrides
./scripts/create-cluster-flux.sh test-account-1 prod-cluster \
  NODE_INSTANCE_TYPE=t3.large \
  NODE_MIN_SIZE=3 \
  NODE_DESIRED_SIZE=5
```

## Directory Structure

```
test-account-1/
├── account/                 # Namespace, IAM, provider config
├── networking/             # VPC and subnets
├── clusters/               # EKS cluster definitions
│   ├── dev-cluster/
│   └── prod-cluster/
├── services/               # Future: RDS, S3, etc.
├── cluster-values.yaml     # Generated after networking is ready
└── kustomization.yaml      # Main kustomization
```

## Resource Dependencies

1. **Account** → Creates namespace and base configuration
2. **Networking** → Creates VPC and subnets (takes ~5 minutes)
3. **Cluster Values** → Generated from live resources
4. **Clusters** → Use cluster values for configuration

## Important Notes

- The `cluster-values.yaml` file is generated after networking is deployed
- This file contains VPC ID and subnet IDs that are only known after creation
- Always run `update-cluster-values.sh` after creating or modifying networking
- Cluster definitions reference these values via Flux variable substitution

## Troubleshooting

### VPC Not Ready
```bash
kubectl describe vpc.network.example.org -n aws-test-account-1 main
kubectl get managed -l crossplane.io/claim-namespace=aws-test-account-1
```

### Missing Cluster Values
```bash
# Regenerate cluster values
./scripts/update-cluster-values.sh test-account-1

# Check ConfigMap in cluster
kubectl get configmap cluster-values -n flux-system -o yaml
```

### Cluster Creation Issues
```bash
# Check Flux kustomization
flux get kustomization cluster-<name>-test-account-1

# Check cluster status
kubectl describe cluster <cluster-name>
```