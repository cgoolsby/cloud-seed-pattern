#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${GREEN}==> $1${NC}"
}

print_info() {
    echo -e "${BLUE}Info: $1${NC}"
}

print_error() {
    echo -e "${RED}Error: $1${NC}"
}

# Check arguments
if [ $# -lt 1 ]; then
    print_error "Missing account alias"
    echo "Usage: $0 <account-alias>"
    echo "Example: $0 test-account-1"
    exit 1
fi

ACCOUNT_ALIAS=$1
ACCOUNT_NAMESPACE="aws-$ACCOUNT_ALIAS"
OUTPUT_FILE="kubernetes/environments/$ACCOUNT_ALIAS/cluster-values.yaml"

print_step "Updating cluster values for $ACCOUNT_ALIAS"

# Get account info
if ! kubectl get namespace $ACCOUNT_NAMESPACE &>/dev/null; then
    print_error "Account namespace $ACCOUNT_NAMESPACE not found"
    exit 1
fi

# Get account details
if kubectl get configmap -n $ACCOUNT_NAMESPACE account-info &>/dev/null; then
    ACCOUNT_ID=$(kubectl get configmap -n $ACCOUNT_NAMESPACE account-info -o jsonpath='{.data.ACCOUNT_ID}')
    ENVIRONMENT=$(kubectl get configmap -n $ACCOUNT_NAMESPACE account-info -o jsonpath='{.data.ENVIRONMENT}')
else
    print_info "account-info ConfigMap not found, using defaults"
    ACCOUNT_ID="UNKNOWN"
    ENVIRONMENT="development"
    
    # Try to get from AWS cluster role identity
    if kubectl get awsclusterroleidentity ${ACCOUNT_ALIAS}-identity &>/dev/null; then
        ROLE_ARN=$(kubectl get awsclusterroleidentity ${ACCOUNT_ALIAS}-identity -o jsonpath='{.spec.roleARN}')
        ACCOUNT_ID=$(echo $ROLE_ARN | cut -d: -f5)
        print_info "Found account ID from AWSClusterRoleIdentity: $ACCOUNT_ID"
    fi
fi

# Get VPC info
VPC_ID=$(kubectl get vpc.network.example.org -n $ACCOUNT_NAMESPACE main -o jsonpath='{.status.vpcId}')
REGION=$(kubectl get vpc.network.example.org -n $ACCOUNT_NAMESPACE main -o jsonpath='{.spec.region}')

# Get subnet IDs
print_step "Getting subnet information..."

# Get private subnets sorted by zone
PRIVATE_SUBNET_A=$(kubectl get subnets -A -l crossplane.io/claim-namespace=$ACCOUNT_NAMESPACE,type=private,zone=a -o jsonpath='{.items[0].status.atProvider.subnetId}')
PRIVATE_SUBNET_B=$(kubectl get subnets -A -l crossplane.io/claim-namespace=$ACCOUNT_NAMESPACE,type=private,zone=b -o jsonpath='{.items[0].status.atProvider.subnetId}')
PRIVATE_SUBNET_C=$(kubectl get subnets -A -l crossplane.io/claim-namespace=$ACCOUNT_NAMESPACE,type=private,zone=c -o jsonpath='{.items[0].status.atProvider.subnetId}')

# Get public subnets sorted by zone
PUBLIC_SUBNET_A=$(kubectl get subnets -A -l crossplane.io/claim-namespace=$ACCOUNT_NAMESPACE,type=public,zone=a -o jsonpath='{.items[0].status.atProvider.subnetId}')
PUBLIC_SUBNET_B=$(kubectl get subnets -A -l crossplane.io/claim-namespace=$ACCOUNT_NAMESPACE,type=public,zone=b -o jsonpath='{.items[0].status.atProvider.subnetId}')
PUBLIC_SUBNET_C=$(kubectl get subnets -A -l crossplane.io/claim-namespace=$ACCOUNT_NAMESPACE,type=public,zone=c -o jsonpath='{.items[0].status.atProvider.subnetId}')

print_step "Generating cluster values ConfigMap..."

cat > "$OUTPUT_FILE" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-values
  namespace: flux-system
data:
  # Account information
  ACCOUNT_ALIAS: "$ACCOUNT_ALIAS"
  ACCOUNT_ID: "$ACCOUNT_ID"
  ENVIRONMENT: "$ENVIRONMENT"
  
  # Network information
  VPC_ID: "$VPC_ID"
  REGION: "$REGION"
  
  # Private subnet IDs
  PRIVATE_SUBNET_A: "$PRIVATE_SUBNET_A"
  PRIVATE_SUBNET_B: "$PRIVATE_SUBNET_B"
  PRIVATE_SUBNET_C: "$PRIVATE_SUBNET_C"
  
  # Public subnet IDs
  PUBLIC_SUBNET_A: "$PUBLIC_SUBNET_A"
  PUBLIC_SUBNET_B: "$PUBLIC_SUBNET_B"
  PUBLIC_SUBNET_C: "$PUBLIC_SUBNET_C"
  
  # EKS configuration defaults
  EKS_VERSION: "v1.28"
  NODE_INSTANCE_TYPE: "t3.medium"
  NODE_MIN_SIZE: "1"
  NODE_MAX_SIZE: "3"
  NODE_DESIRED_SIZE: "2"
  
  # Add-on versions
  VPC_CNI_VERSION: "v1.16.0-eksbuild.1"
  COREDNS_VERSION: "v1.10.1-eksbuild.6"
  KUBE_PROXY_VERSION: "v1.28.5-eksbuild.2"
EOF

print_step "Cluster values saved to $OUTPUT_FILE"
print_info "Values extracted:"
print_info "  VPC ID: $VPC_ID"
print_info "  Region: $REGION"
print_info "  Private Subnets: $PRIVATE_SUBNET_A, $PRIVATE_SUBNET_B, $PRIVATE_SUBNET_C"
print_info "  Public Subnets: $PUBLIC_SUBNET_A, $PUBLIC_SUBNET_B, $PUBLIC_SUBNET_C"

echo ""
echo "Next steps:"
echo "1. Review the generated file: $OUTPUT_FILE"
echo "2. Apply it to the cluster: kubectl apply -f $OUTPUT_FILE"
echo "3. Create clusters using the simplified pattern in clusters/<cluster-name>/"