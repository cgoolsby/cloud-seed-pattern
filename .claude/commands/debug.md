# Debug Command - Troubleshooting Workflows

## Quick System Health Check
```bash
# Overall health
flux check
kubectl get nodes
kubectl get pods -A | grep -v "Running\|Completed" | grep -v "^NAMESPACE"

# Check for recent errors
kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' | tail -20
```

## Component-Specific Debugging

### Debug Flux Issues
```bash
# Check Flux components
flux get sources git -A
flux get kustomization -A
flux get helmrelease -A

# Watch Flux logs
flux logs --follow --all-namespaces

# Check specific Kustomization
flux get kustomization <name> -n flux-system
kubectl describe kustomization <name> -n flux-system
```

### Debug Crossplane Issues
```bash
# Provider health
kubectl get providers
kubectl describe provider provider-aws

# Check ProviderConfigs
kubectl get providerconfigs.aws -A
kubectl describe providerconfig <name>

# View provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws --tail=100

# Check managed resources
kubectl get managed -A
kubectl get composite -A
```

### Debug IRSA Authentication
```bash
# Check service accounts
kubectl get sa -A | grep -E "(aws-load-balancer|external-secrets|ebs-csi|provider-aws)"

# Verify role annotations
kubectl get sa <sa-name> -n <namespace> -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# Test authentication in pod
kubectl run aws-cli-test --image=amazon/aws-cli --rm -it --overrides='{"spec":{"serviceAccount":"<sa-name>"}}' -- sts get-caller-identity
```

### Debug AWS Load Balancer Controller
```bash
# Check controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=50

# Verify webhook
kubectl get validatingwebhookconfigurations aws-load-balancer-webhook
kubectl get mutatingwebhookconfigurations aws-load-balancer-webhook

# Check for ALB/NLB issues
kubectl get ingress -A
kubectl get service -A -o wide | grep -E "LoadBalancer|NodePort"
```

### Debug External Secrets
```bash
# Check operator status
kubectl get deployment -n external-secrets

# View SecretStores
kubectl get secretstores -A
kubectl describe secretstore <name> -n <namespace>

# Check ExternalSecrets
kubectl get externalsecrets -A
kubectl describe externalsecret <name> -n <namespace>

# View operator logs
kubectl logs -n external-secrets deployment/external-secrets --tail=50
```

## Common Issues Quick Fixes

### Flux not syncing
```bash
# Force reconciliation
flux reconcile source git flux-system --with-source
flux reconcile kustomization flux-system

# Check Git connectivity
kubectl get gitrepository flux-system -n flux-system -o yaml | grep -A5 "status:"
```

### Variable substitution not working
```bash
# Check ConfigMap exists
kubectl get cm terraform-outputs -n flux-system -o yaml

# Verify Kustomization has postBuild
kubectl get kustomization <name> -n flux-system -o yaml | grep -A5 "postBuild:"
```

### Resources stuck in terminating
```bash
# Remove finalizers
kubectl patch <resource-type> <name> -p '{"metadata":{"finalizers":null}}' --type=merge

# Force delete
kubectl delete <resource-type> <name> --grace-period=0 --force
```

### Crossplane not creating resources
```bash
# Check for composition errors
kubectl describe composition <name>

# View detailed resource status
kubectl describe <resource-type>.<api-group> <name>

# Check AWS CloudTrail for API calls
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRole --max-items 10
```

## Advanced Debugging

### Enable verbose logging
```bash
# Flux
kubectl edit deployment -n flux-system source-controller
# Add to container args: --log-level=debug

# Crossplane
kubectl edit deployment -n crossplane-system crossplane
# Add to container args: --debug
```

### Check OIDC provider
```bash
# Get OIDC issuer
aws eks describe-cluster --name fullStack-cluster --query "cluster.identity.oidc.issuer" --output text

# List OIDC providers
aws iam list-open-id-connect-providers

# Check trust policy
aws iam get-role --role-name <role-name> --query 'Role.AssumeRolePolicyDocument'
```

### Network troubleshooting
```bash
# Test connectivity from pod
kubectl run netshoot --rm -it --image=nicolaka/netshoot -- /bin/bash

# Inside pod:
nslookup kubernetes.default
curl -k https://kubernetes.default/api/v1/namespaces
```

## Rapid PR Debugging Workflow

### Create Debug Branch for Fast Iteration
When debugging complex issues that require multiple commits, use a feature branch to keep history clean:

```bash
# 1. Create and switch to debug branch
git checkout -b debug/fix-<issue-description>

# 2. Make rapid iterative changes
# Edit files as needed
git add .
git commit -m "WIP: trying fix approach 1"

# Test the fix
flux reconcile source git flux-system --with-source
flux reconcile kustomization <affected-component>

# Continue iterating
git add .
git commit -m "WIP: adjust configuration for X"

# More testing and commits as needed...
```

### Update Flux to Track Debug Branch
```bash
# 1. Update Flux to watch your debug branch
kubectl edit gitrepository flux-system -n flux-system

# 2. Change spec.ref.branch from 'main' to your debug branch:
spec:
  ref:
    branch: debug/fix-<issue-description>

# 3. Force Flux to pull the new branch immediately
flux reconcile source git flux-system --with-source

# 4. Monitor changes taking effect
flux events --watch
```

### Iterate Rapidly Without PR Overhead
```bash
# Now you can push directly to debug branch
git push -u origin debug/fix-<issue-description>

# Flux will automatically apply changes within ~1 minute
# Or force immediate reconciliation:
flux reconcile source git flux-system --with-source

# Check status
flux get kustomization -A
kubectl get pods -A | grep -v Running
```

### Clean Up With Squash Merge
Once the issue is resolved:

```bash
# 1. Create PR from debug branch
gh pr create --base main --head debug/fix-<issue-description> \
  --title "Fix: <issue-description>" \
  --body "## Summary
- Fixed issue with X by doing Y
- Adjusted Z configuration

## Testing
- Verified component deploys successfully
- Confirmed no errors in logs
- Tested functionality

## Changes
<List key changes made>"

# 2. Review the PR diff to ensure it's clean

# 3. Squash and merge via GitHub UI or CLI
gh pr merge --squash --delete-branch

# 4. Switch Flux back to main branch
kubectl edit gitrepository flux-system -n flux-system
# Change spec.ref.branch back to 'main'

# 5. Force reconciliation from main
flux reconcile source git flux-system --with-source

# 6. Clean up local branch
git checkout main
git pull
git branch -d debug/fix-<issue-description>
```

### Alternative: Using Dev Workflow Script
The repository includes a dev workflow script that handles this pattern:

```bash
# This script automates the branch/test/squash workflow
./scripts/dev-workflow.sh start "fixing <issue>"

# Make changes and test
./scripts/dev-workflow.sh test manifests/component.yaml
./scripts/dev-workflow.sh checkpoint "found the issue"

# More changes
./scripts/dev-workflow.sh checkpoint "implemented fix"

# Finish and squash commits
./scripts/dev-workflow.sh finish "Fix: resolved <issue> by adjusting X configuration"
```

### Best Practices for Debug Branches

1. **Naming Convention**: Use `debug/`, `fix/`, or `hotfix/` prefixes
2. **Keep Focused**: One issue per debug branch
3. **Document Progress**: Use descriptive commit messages during debugging
4. **Clean History**: Always squash merge to keep main branch clean
5. **Delete Branches**: Clean up debug branches after merging

### Quick Reference Commands
```bash
# Create debug branch
git checkout -b debug/issue-name

# Update Flux to track branch
kubectl patch gitrepository flux-system -n flux-system --type=merge -p '{"spec":{"ref":{"branch":"debug/issue-name"}}}'

# Push changes
git push -u origin debug/issue-name

# Force Flux sync
flux reconcile source git flux-system --with-source

# Create PR when ready
gh pr create --base main --title "Fix: issue-name"

# Squash merge
gh pr merge --squash --delete-branch

# Switch Flux back to main
kubectl patch gitrepository flux-system -n flux-system --type=merge -p '{"spec":{"ref":{"branch":"main"}}}'
```

## Collect Full Diagnostics
```bash
# Create diagnostics directory
mkdir -p /tmp/k8s-diagnostics

# Collect Flux info
flux check > /tmp/k8s-diagnostics/flux-check.txt
flux get all -A > /tmp/k8s-diagnostics/flux-resources.txt

# Collect pod logs
for ns in flux-system crossplane-system kube-system external-secrets; do
  kubectl logs --all-containers --prefix -n $ns > /tmp/k8s-diagnostics/logs-$ns.txt
done

# Collect events
kubectl get events -A --sort-by='.lastTimestamp' > /tmp/k8s-diagnostics/events.txt

# Package
tar -czf k8s-diagnostics-$(date +%Y%m%d-%H%M%S).tar.gz -C /tmp k8s-diagnostics/
```