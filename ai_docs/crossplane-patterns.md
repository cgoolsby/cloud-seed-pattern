# Crossplane Patterns and Multi-Account Setup

## Overview
This document explains how Crossplane is configured for multi-account AWS resource provisioning in the Cloud Seed Pattern.

## Authentication Architecture

### Management Account Setup
```
EKS OIDC Provider → IRSA → CrossplaneAWSProviderRole → AssumeRole → Target Account
```

1. **IRSA Configuration**: 
   - Role: `CrossplaneAWSProviderRole`
   - Trust: EKS OIDC provider with wildcard service accounts (`provider-aws-*`)
   - Permissions: AssumeRole only

2. **Target Account Access**:
   - Role: `OrganizationAccountAccessRole` (created by AWS Organizations)
   - Trust: Management account role
   - Permissions: Full admin (managed by AWS)

## Account Management Flow

### 1. Account Creation
```hcl
# components/tf_accounts/accounts.tfvars
aws_accounts = [
  {
    name  = "dev-account"
    email = "aws+dev@company.com"
  }
]
```

### 2. ConfigMap Generation
Terraform automatically creates:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-account-dev-account
  namespace: crossplane-system
data:
  accountId: "123456789012"
  accountAlias: "dev-account"
  accountEmail: "aws+dev@company.com"
  roleArn: "arn:aws:iam::123456789012:role/OrganizationAccountAccessRole"
```

### 3. ProviderConfig Creation
```yaml
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: dev-account
spec:
  credentials:
    source: IRSA
  assumeRoleChain:
    - roleARN: arn:aws:iam::123456789012:role/OrganizationAccountAccessRole
```

## Resource Provisioning Patterns

### Pattern 1: Direct Managed Resources
```yaml
apiVersion: ec2.aws.crossplane.io/v1beta1
kind: VPC
metadata:
  name: dev-vpc
  namespace: aws-dev-account
spec:
  forProvider:
    region: us-east-1
    cidrBlock: 10.0.0.0/16
    enableDnsHostnames: true
    enableDnsSupport: true
  providerConfigRef:
    name: dev-account
```

### Pattern 2: Compositions (XRDs)
```yaml
apiVersion: network.example.org/v1alpha1
kind: VPC
metadata:
  name: dev-vpc
  namespace: aws-dev-account
spec:
  parameters:
    region: us-east-1
    cidrBlock: 10.0.0.0/16
    accountName: dev-account  # References ProviderConfig
```

### Pattern 3: Cluster-Scoped Resources
```yaml
apiVersion: network.example.org/v1alpha1
kind: VPCCluster  # Cluster-scoped XR
metadata:
  name: dev-vpc-cluster
spec:
  parameters:
    region: us-east-1
    namespace: aws-dev-account
    accountName: dev-account
```

## VPC Composition Deep Dive

### Known Issues
1. **RouteTable Associations**: The VPC composition has issues with RouteTable creation
2. **AZ Hardcoding**: Assumes regions have 'a' and 'b' availability zones

### VPC Composition Structure
```yaml
# Creates:
- VPC
- InternetGateway + Attachment
- Public Subnets (2)
- Private Subnets (2)
- RouteTables (public/private)
- Routes
- RouteTableAssociations
```

### Working with VPC Compositions
```bash
# Check VPC claim status
kubectl get vpcs.network.example.org -A

# Check composite resource
kubectl get xvpcs

# Debug composition issues
kubectl describe composition vpc-composition

# Check managed resources
kubectl get managed -n crossplane-system | grep vpc
```

## Debugging Crossplane Issues

### 1. Provider Issues
```bash
# Check provider health
kubectl get providers
kubectl describe provider provider-aws

# Check provider pod
kubectl get pods -n crossplane-system | grep provider-aws
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws
```

### 2. IRSA Authentication
```bash
# Verify service account
kubectl get sa -n crossplane-system | grep provider-aws
kubectl describe sa -n crossplane-system provider-aws-*

# Check IAM role assumption
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws | grep AssumeRole
```

### 3. Resource Provisioning
```bash
# Check resource status
kubectl describe vpc.ec2 <name>

# Look for events
kubectl get events -n <namespace> --field-selector involvedObject.name=<resource-name>

# Check ProviderConfig
kubectl describe providerconfig <account-name>
```

## Best Practices

### 1. Namespace Organization
```
aws-<account-alias>/
├── networking/       # VPCs, subnets
├── compute/         # EC2, EKS clusters
├── storage/         # S3, EBS
└── security/        # Security groups, IAM
```

### 2. Resource Naming
- Prefix with account alias: `dev-vpc`, `prod-cluster`
- Use consistent labeling: `account: dev`, `environment: development`
- Match AWS tags with Kubernetes labels

### 3. Composition Design
- Keep compositions focused and modular
- Use parameter validation
- Provide sensible defaults
- Document required vs optional parameters

### 4. Cross-Account Considerations
- Always specify providerConfigRef or accountName
- Verify target account has OrganizationAccountAccessRole
- Test role assumption before creating resources
- Monitor CloudTrail for authentication issues

## Common Scenarios

### Scenario 1: New Environment Setup
```bash
# 1. Add account to Terraform
vim components/tf_accounts/accounts.tfvars

# 2. Create account
cd components/tf_accounts
terraform apply -var-file=accounts.tfvars

# 3. Create GitOps structure
./scripts/gitops-account-setup.sh dev-account

# 4. Deploy networking
git add clusters/dev-account/
git commit -m "Add dev-account environment"
git push
```

### Scenario 2: Cross-Region Resources
```yaml
# Create ProviderConfig for different region
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: dev-account-eu-west-1
spec:
  credentials:
    source: IRSA
  assumeRoleChain:
    - roleARN: ${DEV_ACCOUNT_ROLE_ARN}
  region: eu-west-1  # Override default region
```

### Scenario 3: Resource Dependencies
```yaml
# Use crossplane.io/external-name for references
metadata:
  annotations:
    crossplane.io/external-name: ${vpc_id}
```

## Troubleshooting Checklist

When resources fail to create:

1. [ ] Check Crossplane provider is healthy
2. [ ] Verify ProviderConfig exists and is valid
3. [ ] Confirm IAM role chain works (management → target)
4. [ ] Check resource syntax matches API version
5. [ ] Look for composition rendering errors
6. [ ] Verify target account has necessary AWS service limits
7. [ ] Check CloudTrail for permission errors
8. [ ] Ensure no conflicting resources exist in AWS