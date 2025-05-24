#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${GREEN}==> $1${NC}"
}

print_error() {
    echo -e "${RED}Error: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

# Check if account alias is provided
if [ $# -eq 0 ]; then
    print_error "Please provide account alias as argument"
    echo "Usage: $0 <account-alias>"
    echo "Example: $0 demo-prod"
    exit 1
fi

ACCOUNT_ALIAS=$1
ACCOUNT_NAMESPACE="aws-$ACCOUNT_ALIAS"

print_step "Creating resources for account: $ACCOUNT_ALIAS"

# Step 1: Create namespace for the account
print_step "Creating namespace: $ACCOUNT_NAMESPACE"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $ACCOUNT_NAMESPACE
  labels:
    account.aws/alias: $ACCOUNT_ALIAS
    account.aws/managed-by: platform-team
    purpose: aws-account-resources
EOF

# Step 2: Check if account ConfigMap exists in crossplane-system
print_step "Checking if account ConfigMap exists..."
if ! kubectl get configmap -n crossplane-system aws-account-$ACCOUNT_ALIAS &>/dev/null; then
    print_error "Account ConfigMap aws-account-$ACCOUNT_ALIAS not found in crossplane-system!"
    print_warning "Please run terraform apply in terraform/accounts first"
    exit 1
fi

# Get account details from crossplane-system
ACCOUNT_ID=$(kubectl get configmap -n crossplane-system aws-account-$ACCOUNT_ALIAS -o jsonpath='{.data.ACCOUNT_ID}')
ACCOUNT_ENV=$(kubectl get configmap -n crossplane-system aws-account-$ACCOUNT_ALIAS -o jsonpath='{.data.ENVIRONMENT}')
ACCOUNT_NAME=$(kubectl get configmap -n crossplane-system aws-account-$ACCOUNT_ALIAS -o jsonpath='{.data.ACCOUNT_NAME}')

print_step "Account ID: $ACCOUNT_ID"
print_step "Account Name: $ACCOUNT_NAME"
print_step "Environment: $ACCOUNT_ENV"

# Step 3: Copy account info to the dedicated namespace
print_step "Copying account information to $ACCOUNT_NAMESPACE..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: account-info
  namespace: $ACCOUNT_NAMESPACE
  labels:
    account.aws/alias: $ACCOUNT_ALIAS
data:
  ACCOUNT_ID: "$ACCOUNT_ID"
  ACCOUNT_NAME: "$ACCOUNT_NAME"
  ACCOUNT_ALIAS: "$ACCOUNT_ALIAS"
  ENVIRONMENT: "$ACCOUNT_ENV"
  NAMESPACE: "$ACCOUNT_NAMESPACE"
EOF

# Step 4: Create Crossplane ProviderConfig
print_step "Creating Crossplane ProviderConfig..."
cat <<EOF | kubectl apply -f -
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: $ACCOUNT_ALIAS
spec:
  credentials:
    source: InjectedIdentity
  assumeRoleARN: arn:aws:iam::${ACCOUNT_ID}:role/OrganizationAccountAccessRole
EOF

# Step 5: Create CAPA IAM roles in the account namespace
print_step "Creating CAPA IAM roles claim..."
cat <<EOF | kubectl apply -f -
apiVersion: aws.platform.io/v1alpha1
kind: CAPAIAMRoles
metadata:
  name: capa-iam
  namespace: $ACCOUNT_NAMESPACE
spec:
  region: us-west-2
  accountId: "$ACCOUNT_ID"
  providerConfigRef:
    name: $ACCOUNT_ALIAS
  tags:
    Environment: $ACCOUNT_ENV
    ManagedBy: crossplane
    Purpose: cluster-api
    AccountAlias: $ACCOUNT_ALIAS
EOF

# Step 6: Create VPC claim
print_step "Creating VPC claim..."
# Determine CIDR based on environment or use a default
case $ACCOUNT_ENV in
  "production")
    CIDR="10.0.0.0/16"
    ;;
  "staging")
    CIDR="10.1.0.0/16"
    ;;
  "development")
    CIDR="10.2.0.0/16"
    ;;
  *)
    CIDR="10.100.0.0/16"
    ;;
esac

cat <<EOF | kubectl apply -f -
apiVersion: aws.platform.io/v1alpha1
kind: VPC
metadata:
  name: main
  namespace: $ACCOUNT_NAMESPACE
spec:
  region: us-west-2
  providerConfigRef:
    name: $ACCOUNT_ALIAS
  cidrBlock: "$CIDR"
  enableDnsSupport: true
  enableDnsHostnames: true
  tags:
    Name: $ACCOUNT_ALIAS-main-vpc
    Environment: $ACCOUNT_ENV
    ManagedBy: crossplane
    Purpose: eks-clusters
    AccountAlias: $ACCOUNT_ALIAS
EOF

# Step 7: Create CAPA identity for the account (this stays in default namespace)
print_step "Creating CAPA cluster role identity..."
cat <<EOF | kubectl apply -f -
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: AWSClusterRoleIdentity
metadata:
  name: $ACCOUNT_ALIAS-identity
  namespace: default
spec:
  allowedNamespaces:
    list:
    - default
    - $ACCOUNT_NAMESPACE
  roleARN: arn:aws:iam::${ACCOUNT_ID}:role/OrganizationAccountAccessRole
  sourceIdentityRef:
    kind: AWSClusterControllerIdentity
    name: default
EOF

# Step 8: Create RBAC for the namespace
print_step "Creating RBAC for namespace access..."
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: account-resources-viewer
  namespace: $ACCOUNT_NAMESPACE
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["aws.platform.io"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["ec2.aws.crossplane.io", "iam.aws.crossplane.io"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: account-resources-viewer-binding
  namespace: $ACCOUNT_NAMESPACE
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: account-resources-viewer
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:authenticated
EOF

print_step "Waiting for resources to be ready..."
sleep 10

# Check CAPA IAM status
print_step "Checking CAPA IAM roles status..."
kubectl wait --for=condition=Ready capaiamroles -n $ACCOUNT_NAMESPACE capa-iam --timeout=300s || print_warning "CAPA IAM roles not ready yet"

# Check VPC status
print_step "Checking VPC status..."
kubectl wait --for=condition=Ready vpc -n $ACCOUNT_NAMESPACE main --timeout=300s || print_warning "VPC not ready yet"

# Get VPC ID
VPC_ID=$(kubectl get vpc -n $ACCOUNT_NAMESPACE main -o jsonpath='{.status.atProvider.vpcId}' 2>/dev/null || echo "pending")
print_step "VPC ID: $VPC_ID"

# Summary
print_step "Account resources created successfully!"
echo ""
echo "Namespace: $ACCOUNT_NAMESPACE"
echo "Resources created:"
echo "  - Namespace with account labels"
echo "  - Account information ConfigMap"
echo "  - CAPA IAM roles"
echo "  - VPC with CIDR: $CIDR"
echo "  - CAPA cluster role identity"
echo ""
echo "Next steps:"
echo "1. Wait for all resources to be ready:"
echo "   kubectl get capaiamroles,vpc -n $ACCOUNT_NAMESPACE"
echo ""
echo "2. Create a cluster using:"
echo "   ./scripts/create-cluster.sh $ACCOUNT_ALIAS <cluster-name>"
echo ""
echo "To check resource status:"
echo "  kubectl -n $ACCOUNT_NAMESPACE get all,capaiamroles,vpc"
echo "  kubectl -n $ACCOUNT_NAMESPACE describe capaiamroles capa-iam"
echo "  kubectl -n $ACCOUNT_NAMESPACE describe vpc main"