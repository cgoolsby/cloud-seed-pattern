# Component Installation Patterns

## Overview
This document describes the standardized patterns for installing components in the Cloud Seed Pattern repository.

## Component Structure

### 1. Base Component Definition
Located in `components/helmrelease/<component-name>/`:
- `helmrepository.yaml` - Helm chart repository definition
- `helmrelease.yaml` - Helm release configuration with values
- `kustomization.yaml` - Kustomize file bundling resources
- `namespace.yaml` - Namespace definition (if needed)

### 2. Cluster Integration
Located in `clusters/<cluster-path>/<component-name>/`:
- `kustomization.yaml` - References the base component
- May include patches for cluster-specific overrides

### 3. Flux Kustomization
Located in `clusters/<cluster-path>/<component-name>.yaml`:
- Flux Kustomization resource that deploys the component
- Includes dependencies, variable substitution, and reconciliation settings

## Variable Substitution Pattern

### From Terraform Outputs
```yaml
postBuild:
  substituteFrom:
    - kind: ConfigMap
      name: terraform-outputs
```

Common variables:
- `${ALB_CONTROLLER_ROLE_ARN}` - AWS LB Controller IAM role
- `${EBS_CSI_ROLE_ARN}` - EBS CSI Driver IAM role
- `${EXTERNAL_SECRETS_ROLE_ARN}` - External Secrets IAM role
- `${CLUSTER_NAME}` - EKS cluster name
- `${VPC_ID}` - VPC identifier
- `${REGION}` - AWS region

### From Account ConfigMaps
For multi-account resources:
```yaml
postBuild:
  substituteFrom:
    - kind: ConfigMap
      name: aws-account-<alias>
      namespace: crossplane-system
```

## Component Categories

### 1. System Components
Essential for cluster operation:
- **cert-manager**: Certificate management
- **external-secrets**: Secret synchronization
- **aws-ebs-csi**: Persistent volume support
- **aws-load-balancer-controller**: Load balancer provisioning

### 2. Platform Components
Core platform capabilities:
- **crossplane**: Infrastructure provisioning
- **cluster-api**: Cluster lifecycle management
- **flux-system**: GitOps engine (bootstrapped separately)

### 3. Observability Components
Monitoring and logging:
- **monitoring**: Prometheus/Grafana stack
- **logging**: Loki/Promtail stack

### 4. Application Components
Business applications:
- **supabase**: Backend-as-a-Service platform

## Installation Checklist

When adding a new component:

1. **Component Definition**:
   - [ ] Create component in `components/helmrelease/<name>/`
   - [ ] Define HelmRepository if new chart source
   - [ ] Configure HelmRelease with appropriate values
   - [ ] Add namespace.yaml if component needs dedicated namespace
   - [ ] Create kustomization.yaml to bundle resources

2. **IRSA Setup** (if AWS access needed):
   - [ ] Add IAM role in `components/tf_initialSeedCluster/`
   - [ ] Export role ARN to terraform-outputs ConfigMap
   - [ ] Reference in HelmRelease serviceAccount annotations

3. **Cluster Integration**:
   - [ ] Create directory `clusters/<path>/<component>/`
   - [ ] Add kustomization.yaml referencing base component
   - [ ] Create Flux Kustomization in `clusters/<path>/<component>.yaml`
   - [ ] Add to cluster's main kustomization.yaml resources

4. **Dependencies**:
   - [ ] Identify component dependencies
   - [ ] Add dependsOn in Flux Kustomization
   - [ ] Ensure proper startup order

5. **Testing**:
   - [ ] Test with dev-workflow.sh before committing
   - [ ] Verify IRSA authentication works
   - [ ] Check resource creation and health

## Common Patterns

### Pattern 1: Simple Helm Release
```yaml
# Flux Kustomization
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <component>
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./clusters/<path>/<component>
  prune: true
  timeout: 5m
```

### Pattern 2: With IRSA
```yaml
# Include variable substitution
spec:
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: terraform-outputs
```

### Pattern 3: With Dependencies
```yaml
# Ensure startup order
spec:
  dependsOn:
    - name: cert-manager
    - name: external-secrets
```

### Pattern 4: Multi-Account Resource
```yaml
# Reference account ConfigMap
spec:
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: aws-account-dev
        namespace: crossplane-system
```

## Troubleshooting

### Component Not Installing
1. Check Flux Kustomization status: `flux get kustomization <name>`
2. Check events: `flux events --for Kustomization/<name>`
3. Verify path in Flux Kustomization matches actual directory
4. Check dependencies are healthy

### IRSA Not Working
1. Verify IAM role exists: Check Terraform outputs
2. Check service account annotation: `kubectl describe sa <name> -n <namespace>`
3. Verify OIDC provider trust relationship
4. Check pod has AWS environment variables

### Variable Substitution Failed
1. Verify ConfigMap exists: `kubectl get cm terraform-outputs -n flux-system`
2. Check variable syntax: `${VARIABLE_NAME}`
3. Ensure postBuild.substituteFrom is configured
4. Look for typos in variable names