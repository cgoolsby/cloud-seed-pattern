# AI Documentation Directory

This directory contains documentation specifically written to help AI assistants (like Claude) understand and work with the Cloud Seed Pattern repository effectively.

## Purpose

These documents provide:
- Deep architectural context
- Common patterns and workflows  
- Troubleshooting guidance
- Quick reference materials
- Implementation details not obvious from code

## Document Overview

### Core Understanding
- **architecture-overview.md**: High-level system design, component relationships, and key design decisions
- **quick-reference.md**: Essential commands, common tasks, and directory structure

### Implementation Patterns
- **component-patterns.md**: Standardized patterns for installing and configuring components
- **crossplane-patterns.md**: Multi-account setup, authentication flow, and resource provisioning
- **gitops-workflows.md**: Development workflows, Flux patterns, and best practices

### Operational Guidance
- **troubleshooting-guide.md**: Common issues, debugging commands, and solutions
- **missing-scripts-todo.md**: Scripts referenced but not yet implemented

## How to Use These Docs

1. **First Time**: Read `architecture-overview.md` to understand the system
2. **Installing Components**: Follow patterns in `component-patterns.md`
3. **Debugging Issues**: Consult `troubleshooting-guide.md`
4. **Daily Work**: Keep `quick-reference.md` handy
5. **Multi-Account Work**: Reference `crossplane-patterns.md`

## Key Concepts to Understand

### IRSA (IAM Roles for Service Accounts)
- No static credentials anywhere
- Pods assume IAM roles via OIDC
- Wildcard trust for dynamic service accounts

### GitOps with Flux
- Git is the source of truth
- All changes through commits
- Flux reconciles continuously
- Variable substitution via ConfigMaps

### Multi-Account Architecture
- Management account hosts Crossplane
- Target accounts have OrganizationAccountAccessRole
- Cross-account access via role chaining
- Account details in auto-generated ConfigMaps

### Component Dependencies
```
Terraform (Bootstrap) → Flux → Cert-Manager → Other Components
                            ↘ Crossplane → AWS Resources
                            ↘ Cluster API → Workload Clusters
```

## Important Patterns

### Variable Substitution
Only works in Flux Kustomizations with `postBuild.substituteFrom`:
```yaml
postBuild:
  substituteFrom:
    - kind: ConfigMap
      name: terraform-outputs
```

### Directory Organization
- `components/`: Reusable definitions
- `clusters/<name>/`: Cluster-specific configs
- `scripts/`: Automation tools

### Development Workflow
1. Use `dev-workflow.sh` for local testing
2. Create PRs for production changes
3. Let Flux handle deployment
4. Monitor with `flux events --watch`

## Common Gotchas

1. **VPC Composition**: Has RouteTable association issues
2. **AZ Assumptions**: Assumes 'a' and 'b' availability zones
3. **Direct kubectl**: Avoid in production, use GitOps
4. **Variable Syntax**: Must use `${VARIABLE_NAME}` format
5. **Script Gaps**: Some scripts in CLAUDE.md don't exist yet

## Quick Wins

- Run `flux check` for system health
- Use `flux get all -A` for resource overview
- Check `kubectl get events -A` for recent issues
- Force sync with `flux reconcile source git flux-system`
- Debug IRSA with pod's `aws sts get-caller-identity`

## Need More Context?

1. Check CLAUDE.md for specific instructions
2. Review actual component definitions in `components/`
3. Look at working examples in `clusters/management/primary/`
4. Examine scripts in `scripts/` for automation patterns