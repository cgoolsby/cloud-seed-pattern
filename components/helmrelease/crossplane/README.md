# Crossplane with IAM Roles for Service Accounts (IRSA)

This directory contains the necessary configuration for deploying Crossplane with AWS provider support for cross-account access using IAM Roles for Service Accounts (IRSA).

## Architecture Overview

The configuration enables Crossplane to:
1. Run in the management cluster with IRSA
2. Assume roles in child AWS accounts
3. Create networking resources (VPCs, subnets, etc.) in child accounts
4. Create IAM roles in child accounts for cluster workloads

## IAM Setup Requirements

### 1. Management Account IAM Setup

Create roles in your management account that Crossplane will use:

```bash
# Set variables
MANAGEMENT_ACCOUNT_ID=<your-management-account-id>
OIDC_PROVIDER=<your-eks-oidc-provider-id> # e.g. oidc.eks.region.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE

# Create IAM policy for Crossplane AWS provider
aws iam create-policy \
  --policy-name CrossplaneAWSProviderPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ec2:*",
          "iam:*",
          "eks:*",
          "elasticloadbalancing:*",
          "kms:*",
          "route53:*",
          "s3:*",
          "vpc:*",
          "sts:AssumeRole"
        ],
        "Resource": "*"
      }
    ]
  }'

# Create IAM role for Crossplane AWS provider with trust relationship to ServiceAccount
aws iam create-role \
  --role-name CrossplaneAWSProviderRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::'${MANAGEMENT_ACCOUNT_ID}':oidc-provider/'${OIDC_PROVIDER}'"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "'${OIDC_PROVIDER}':sub": "system:serviceaccount:crossplane-system:provider-aws-controller"
          }
        }
      }
    ]
  }'

# Attach policy to role
aws iam attach-role-policy \
  --role-name CrossplaneAWSProviderRole \
  --policy-arn arn:aws:iam::${MANAGEMENT_ACCOUNT_ID}:policy/CrossplaneAWSProviderPolicy
```

### 2. Child Account IAM Setup

For each child account where you want to provision resources, create a role that allows the management account to assume it:

```bash
# Set variables
CHILD_ACCOUNT_ID=<your-child-account-id>
MANAGEMENT_ACCOUNT_ID=<your-management-account-id>

# Create IAM policy for Crossplane resource provisioning
aws iam create-policy \
  --policy-name CrossplaneProviderPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ec2:*",
          "iam:*",
          "eks:*",
          "elasticloadbalancing:*",
          "kms:*",
          "route53:*",
          "s3:*",
          "vpc:*"
        ],
        "Resource": "*"
      }
    ]
  }'

# Create IAM role for Crossplane with trust relationship to management account role
aws iam create-role \
  --role-name CrossplaneProviderRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::'${MANAGEMENT_ACCOUNT_ID}':role/CrossplaneAWSProviderRole"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }'

# Attach policy to role
aws iam attach-role-policy \
  --role-name CrossplaneProviderRole \
  --policy-arn arn:aws:iam::${CHILD_ACCOUNT_ID}:policy/CrossplaneProviderPolicy
```

## Configuration Files Update

After creating the IAM roles, update the following files with your actual account IDs:

1. `crossplane-core.yaml`: Replace `<MANAGEMENT_ACCOUNT_ID>` with your management AWS account ID.
2. `aws-iam.yaml`: 
   - Replace `<MANAGEMENT_ACCOUNT_ID>` with your management AWS account ID.
   - Replace `<CHILD_ACCOUNT_ID>` with your child AWS account ID.
3. `providers/provider-aws-config.yaml`: Update the child account reference if needed.

## Using Compositions

### Creating a VPC in a Child Account

```yaml
apiVersion: network.example.org/v1alpha1
kind: VPC
metadata:
  name: production-vpc
  namespace: default
spec:
  region: us-east-1
  cidrBlock: 10.0.0.0/16
  accountName: child-account-1  # References the provider config for the child account
  publicSubnetCIDRs:
    - 10.0.0.0/24
    - 10.0.1.0/24
  privateSubnetCIDRs:
    - 10.0.2.0/24
    - 10.0.3.0/24
```

### Creating an IAM Role in a Child Account

```yaml
apiVersion: iam.example.org/v1alpha1
kind: ClusterRole
metadata:
  name: eks-worker-role
  namespace: default
spec:
  accountName: child-account-1  # References the provider config for the child account
  roleName: eks-worker-role
  clusterName: production-cluster
  namespace: kube-system
  serviceAccountName: aws-node
  trustAccounts:
    - "123456789012"  # AWS account ID that can assume this role
```

## Security Considerations

- The IAM roles created in this setup follow the principle of least privilege
- Cross-account access is restricted to specific roles and actions
- Consider restricting the policies further based on your specific requirements
- For production environments, regularly audit the permissions granted to these roles
