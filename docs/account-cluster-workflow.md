# AWS Account and Cluster Management Workflow

This document describes the complete GitOps workflow for creating new AWS accounts, setting up networking, and deploying EKS clusters.

## Overview

The workflow follows these principles:
- **GitOps First**: All resources are managed through Git commits and Flux
- **Namespace Isolation**: Each AWS account gets its own namespace (`aws-<account-alias>`)
- **Template-Based**: Standardized templates ensure consistency
- **Automated**: Flux automatically reconciles all changes

## Architecture

```
kubernetes/
├── accounts/              # AWS account resources
│   ├── base/             # Base templates
│   └── overlays/         # Per-account configurations
├── clusters/             # Cluster definitions
│   ├── base/             # Base cluster templates
│   └── <account>/        # Clusters per account
└── base/
    └── flux-system/      # Flux kustomizations
```

## Workflow Steps

### 1. Create AWS Account (Terraform)

First, create the AWS account using Terraform:

```bash
cd terraform/accounts

# Edit accounts.tfvars to add new account
vi accounts.tfvars

# Example addition:
# "demo-prod" = {
#   name        = "Demo Production"
#   email       = "demo-prod@example.com"
#   environment = "production"
# }

# Apply changes
terraform plan -var-file=accounts.tfvars
terraform apply -var-file=accounts.tfvars
```

### 2. Generate GitOps Configuration

Use the helper script to create the GitOps configuration:

```bash
# From repository root
./scripts/gitops-account-setup.sh demo-prod
```

This creates:
- Namespace configuration
- Crossplane ProviderConfig
- CAPA IAM roles claim
- VPC claim
- CAPA cluster role identity

### 3. Commit and Push

```bash
git add kubernetes/accounts/overlays/demo-prod
git add kubernetes/accounts/overlays/kustomization.yaml
git commit -m "Add GitOps configuration for demo-prod account"
git push
```

### 4. Monitor Deployment

Flux will automatically create all resources:

```bash
# Watch Flux kustomizations
flux get kustomizations --watch

# Check account namespace
kubectl get ns aws-demo-prod

# Monitor resource creation
kubectl -n aws-demo-prod get capaiamroles,vpc --watch

# Check detailed status
kubectl -n aws-demo-prod describe capaiamroles capa-iam
kubectl -n aws-demo-prod describe vpc main
```

### 5. Create Cluster Configuration

Once account resources are ready, create a cluster:

```bash
# Create cluster directory
mkdir -p kubernetes/clusters/demo-prod

# Create cluster configuration
cat > kubernetes/clusters/demo-prod/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: default  # Or create a dedicated namespace

resources:
  - ../../base/eks-cluster

# Cluster-specific configuration
namePrefix: demo-
nameSuffix: -prod

patches:
  - target:
      kind: Cluster
      name: CLUSTER-NAME
    patch: |-
      - op: replace
        path: /metadata/name
        value: demo-cluster-prod
        
  - target:
      kind: AWSManagedControlPlane
      name: CLUSTER-NAME-control-plane
    patch: |-
      - op: replace
        path: /metadata/name
        value: demo-cluster-prod-control-plane
      - op: replace
        path: /spec/identityRef/name
        value: demo-prod-identity
      - op: replace
        path: /spec/network/vpc/id
        value: \${VPC_ID}  # Get from kubectl get vpc -n aws-demo-prod

  - target:
      kind: MachinePool
      name: CLUSTER-NAME-pool-0
    patch: |-
      - op: replace
        path: /metadata/name
        value: demo-cluster-prod-pool-0
      - op: replace
        path: /spec/clusterName
        value: demo-cluster-prod

  - target:
      kind: AWSManagedMachinePool
      name: CLUSTER-NAME-pool-0
    patch: |-
      - op: replace
        path: /metadata/name
        value: demo-cluster-prod-pool-0
      - op: replace
        path: /spec/eksNodegroupName
        value: demo-cluster-prod-ng-0
EOF
```

### 6. Add Cluster to Flux

Create a Flux kustomization for the cluster:

```bash
cat > kubernetes/clusters/demo-prod/flux-kustomization.yaml <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster-demo-prod
  namespace: flux-system
spec:
  interval: 5m0s
  path: ./kubernetes/clusters/demo-prod
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: accounts  # Wait for account resources
  wait: true
  timeout: 30m0s
EOF
```

### 7. Deploy Cluster

```bash
# Commit cluster configuration
git add kubernetes/clusters/demo-prod
git commit -m "Add demo-prod EKS cluster"
git push

# Monitor cluster creation
kubectl get clusters -w
kubectl describe cluster demo-cluster-prod
```

## Resource Dependencies

The GitOps workflow ensures proper ordering:

1. **Terraform** → Creates AWS account and ConfigMaps
2. **Accounts Kustomization** → Creates namespace, IAM, VPC
3. **Cluster Kustomization** → Creates EKS cluster using account resources

## Troubleshooting

### Check Flux Status
```bash
flux get all
flux logs --all-namespaces --follow
```

### Check Account Resources
```bash
# List all account namespaces
kubectl get ns -l purpose=aws-account-resources

# Check specific account
kubectl -n aws-<account-alias> get all,capaiamroles,vpc
```

### Check Crossplane Status
```bash
kubectl get providerconfigs.aws.crossplane.io
kubectl get managed -l crossplane.io/claim-namespace=aws-<account-alias>
```

### Common Issues

1. **VPC Not Ready**: Check Crossplane provider and IAM permissions
2. **CAPA IAM Failed**: Verify account ID and provider config
3. **Cluster Stuck**: Check CAPA controller logs and IAM roles

## Best Practices

1. **Use Templates**: Always start from templates, don't create from scratch
2. **Test in Dev**: Create development account first to test changes
3. **Monitor Flux**: Keep `flux get all --watch` running during deployments
4. **Check Dependencies**: Ensure account resources are ready before creating clusters
5. **Use GitOps**: Never apply resources directly with kubectl

## Next Steps

- Set up cluster autoscaling
- Configure cluster addons (ingress, monitoring, etc.)
- Implement cluster backup strategies
- Set up multi-region deployments