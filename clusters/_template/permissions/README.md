# Permissions Configuration

This directory contains the IAM permissions required for Cluster API (CAPA) to manage EKS clusters.

## Resources

1. **capa-iam-roles.yaml** - Creates the required IAM roles for EKS control plane, nodes, and Fargate
2. **cluster-role-identity.yaml** - Creates the AWSClusterRoleIdentity for CAPA authentication
3. **permissions-configmap.yaml** - Stores IAM role ARNs and permission values

## Configuration

The following variables need to be set when using this template:

- `${CLUSTER_NAME}` - Name of the cluster
- `${ACCOUNT_NAMESPACE}` - Namespace for the account (e.g., aws-test-account-1)
- `${ACCOUNT_NAME}` - Account alias for the ProviderConfig
- `${ACCOUNT_ID}` - AWS Account ID
- `${REGION}` - AWS region
- `${ENVIRONMENT}` - Environment tag

## Created IAM Roles

The CAPAIAMRoles resource creates:
1. **Control Plane Role** - For EKS control plane operations
2. **Node Role** - For EC2 nodes to join the cluster
3. **Fargate Role** - For Fargate profiles (if used)

All roles are created with appropriate trust policies and managed policies for EKS operation.

## Usage

The cluster definition should reference:
- The AWSClusterRoleIdentity in the AWSCluster spec
- The control plane role ARN in the AWSManagedControlPlane spec
- The node role ARN in the AWSManagedMachinePool spec