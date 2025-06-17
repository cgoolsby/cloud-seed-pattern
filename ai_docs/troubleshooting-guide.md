# Troubleshooting Guide

## Quick Diagnostics

### System Health Check
```bash
# 1. Flux health
flux check

# 2. Core components
kubectl get pods -n flux-system
kubectl get pods -n crossplane-system
kubectl get pods -n kube-system | grep -E "(aws-load|ebs-csi|external-secrets)"

# 3. Check for errors
kubectl get events -A --sort-by='.lastTimestamp' | grep -i error | tail -20
```

## Component-Specific Troubleshooting

### Flux Issues

#### Symptom: Kustomization stuck in "Not Ready"
```bash
# Get detailed status
flux get kustomization <name> -n flux-system

# Check events
kubectl describe kustomization <name> -n flux-system

# View logs
flux logs --kind=Kustomization --name=<name>

# Common fixes:
# 1. Check path exists in Git
# 2. Verify dependencies are healthy
# 3. Look for YAML syntax errors
# 4. Check variable substitution
```

#### Symptom: GitRepository not updating
```bash
# Force reconciliation
flux reconcile source git flux-system

# Check SSH key/token
kubectl get secret flux-system -n flux-system -o yaml

# Verify webhook (if configured)
flux get receivers
```

### Crossplane Issues

#### Symptom: AWS resources not creating
```bash
# 1. Check provider
kubectl get providers
kubectl describe provider provider-aws

# 2. Verify ProviderConfig
kubectl get providerconfigs.aws
kubectl describe providerconfig <name>

# 3. Check managed resource
kubectl describe <resource-type> <name>

# 4. Provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws
```

#### Symptom: IRSA authentication failing
```bash
# Check service account
kubectl get sa -n crossplane-system | grep provider-aws
kubectl describe sa -n crossplane-system provider-aws-*

# Verify role trust policy
aws iam get-role --role-name CrossplaneAWSProviderRole \
  --query 'Role.AssumeRolePolicyDocument'

# Test assume role
aws sts assume-role \
  --role-arn arn:aws:iam::<account>:role/OrganizationAccountAccessRole \
  --role-session-name test
```

### AWS Load Balancer Controller Issues

#### Symptom: Load balancers not creating
```bash
# Check controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Verify IAM permissions
kubectl get sa aws-load-balancer-controller -n kube-system -o yaml

# Check ingress/service annotations
kubectl describe ingress <name>
kubectl describe service <name>
```

#### Common annotation issues:
```yaml
# For ALB
metadata:
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip

# For NLB
metadata:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
```

### External Secrets Issues

#### Symptom: Secrets not syncing
```bash
# Check operator logs
kubectl logs -n external-secrets deployment/external-secrets

# Verify SecretStore
kubectl get secretstores -A
kubectl describe secretstore <name>

# Check ExternalSecret status
kubectl get externalsecrets -A
kubectl describe externalsecret <name>

# Test AWS Secrets Manager access
aws secretsmanager get-secret-value \
  --secret-id <secret-name> --region <region>
```

### Cluster API Issues

#### Symptom: Cluster stuck in provisioning
```bash
# Check cluster status
kubectl get clusters -A
kubectl describe cluster <name>

# Check machine status
kubectl get machines -A
kubectl describe machine <name>

# CAPA controller logs
kubectl logs -n capa-system deployment/capa-controller-manager

# Check AWS resources
aws eks describe-cluster --name <cluster-name>
aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/<name>,Values=owned"
```

## Common Patterns and Fixes

### Pattern: Variable substitution not working
```yaml
# Symptom: ${VARIABLE} appearing literally in resources

# Fix 1: Verify ConfigMap exists
kubectl get cm terraform-outputs -n flux-system

# Fix 2: Check Kustomization has postBuild
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
spec:
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: terraform-outputs

# Fix 3: Ensure variable name matches exactly
kubectl get cm terraform-outputs -n flux-system -o yaml
```

### Pattern: Dependency deadlock
```bash
# Symptom: Multiple resources waiting on each other

# Identify cycle
flux get kustomizations --show-graph

# Break cycle by:
# 1. Temporarily removing dependsOn
# 2. Manual creation of missing resource
# 3. Re-adding dependsOn after resolution
```

### Pattern: Namespace issues
```yaml
# Symptom: Resources created in wrong namespace

# Fix: Ensure namespace in manifest
metadata:
  name: resource-name
  namespace: correct-namespace  # Always specify

# Or use Kustomization namePrefix/namespace
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: target-namespace
```

### Pattern: IRSA role not working
```bash
# Symptom: 403 errors, AccessDenied

# Debug steps:
# 1. Get pod and check AWS env vars
kubectl exec -it <pod> -- env | grep AWS

# 2. Test token exchange
kubectl exec -it <pod> -- aws sts get-caller-identity

# 3. Verify OIDC provider
aws eks describe-cluster --name <cluster> \
  --query 'cluster.identity.oidc.issuer'

# 4. Check trust policy has correct OIDC
aws iam get-role --role-name <role> \
  --query 'Role.AssumeRolePolicyDocument.Statement[].Principal'
```

## Emergency Procedures

### Rollback Deployment
```bash
# Option 1: Git revert
git revert HEAD
git push

# Option 2: Suspend and fix
flux suspend kustomization <name>
kubectl apply -f previous-working-manifest.yaml
flux resume kustomization <name>

# Option 3: Branch switch
kubectl edit gitrepository flux-system
# Change spec.ref.branch to stable branch
```

### Break Glass Access
```bash
# If Flux is broken, apply directly
kubectl apply -f emergency-fix.yaml

# Sync Flux afterward
flux reconcile source git flux-system --with-source
```

### Resource Cleanup
```bash
# Delete stuck resources
kubectl delete <resource> <name> --force --grace-period=0

# Remove finalizers if needed
kubectl patch <resource> <name> -p '{"metadata":{"finalizers":[]}}' --type=merge
```

## Debug Commands Cheatsheet

```bash
# Flux
flux events --watch
flux get all -A
flux logs --all-namespaces --follow

# Crossplane
kubectl get managed -A
kubectl get composite -A
kubectl get providers

# General Kubernetes
kubectl api-resources --verbs=list -o name | xargs -n 1 kubectl get -A
kubectl get events -A --sort-by='.lastTimestamp'
kubectl top nodes
kubectl top pods -A

# AWS
aws sts get-caller-identity
aws iam list-roles | grep -i crossplane
aws eks describe-cluster --name <cluster>
```

## Performance Optimization

### Flux Performance
```yaml
# Increase concurrency
apiVersion: v1
kind: ConfigMap
metadata:
  name: flux-system
  namespace: flux-system
data:
  concurrent: "10"  # Default is 4
```

### Reduce reconciliation frequency
```yaml
spec:
  interval: 30m  # Increase for stable resources
```

### Crossplane Performance
```yaml
# Increase provider package revision limit
apiVersion: pkg.crossplane.io/v1
kind: Provider
spec:
  packageRevisionLimit: 5  # Keep more revisions
```

## Getting Help

### Collect diagnostics
```bash
# Create support bundle
./scripts/collect-diagnostics.sh

# Includes:
# - flux check output
# - All pod logs
# - Resource descriptions
# - Recent events
# - Git repository state
```

### Useful resources
- Flux docs: https://fluxcd.io/docs/
- Crossplane docs: https://crossplane.io/docs/
- CAPI docs: https://cluster-api.sigs.k8s.io/
- AWS EKS best practices: https://aws.github.io/aws-eks-best-practices/