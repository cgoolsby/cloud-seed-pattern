#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${GREEN}==> $1${NC}" >&2
}

print_info() {
    echo -e "${BLUE}Info: $1${NC}" >&2
}

print_error() {
    echo -e "${RED}Error: $1${NC}" >&2
}

# Check arguments
if [ $# -lt 3 ]; then
    print_error "Missing arguments"
    echo "Usage: $0 <account-alias> <cluster-name> <networking-name>"
    echo "Example: $0 test-account-1 dev-cluster main"
    exit 1
fi

ACCOUNT_ALIAS=$1
CLUSTER_NAME=$2
NETWORKING_NAME=$3
ACCOUNT_NAMESPACE="aws-$ACCOUNT_ALIAS"

print_step "Generating cluster configuration for $CLUSTER_NAME"

# Get account info
if ! kubectl get configmap -n $ACCOUNT_NAMESPACE account-info &>/dev/null; then
    print_error "account-info ConfigMap not found in namespace $ACCOUNT_NAMESPACE"
    exit 1
fi

ACCOUNT_ID=$(kubectl get configmap -n $ACCOUNT_NAMESPACE account-info -o jsonpath='{.data.ACCOUNT_ID}')
ENVIRONMENT=$(kubectl get configmap -n $ACCOUNT_NAMESPACE account-info -o jsonpath='{.data.ENVIRONMENT}')
REGION=$(kubectl get configmap -n $ACCOUNT_NAMESPACE account-info -o jsonpath='{.data.REGION}' 2>/dev/null || echo "")

# If REGION is not in account-info, try to get from VPC
if [ -z "$REGION" ]; then
    REGION=$(kubectl get vpc.network.example.org -n $ACCOUNT_NAMESPACE $NETWORKING_NAME -o jsonpath='{.spec.region}' 2>/dev/null || echo "us-west-2")
fi

print_info "Account ID: $ACCOUNT_ID"
print_info "Environment: $ENVIRONMENT"
print_info "Region: $REGION"

# Get networking info
if ! kubectl get configmap -n $ACCOUNT_NAMESPACE ${NETWORKING_NAME}-networking &>/dev/null; then
    print_error "${NETWORKING_NAME}-networking ConfigMap not found"
    print_info "Looking for actual VPC resources..."
    
    # Try to get from live resources
    if kubectl get vpc.network.example.org -n $ACCOUNT_NAMESPACE $NETWORKING_NAME &>/dev/null; then
        VPC_ID=$(kubectl get vpc.network.example.org -n $ACCOUNT_NAMESPACE $NETWORKING_NAME -o jsonpath='{.status.vpcId}')
        VPC_CIDR=$(kubectl get vpc.network.example.org -n $ACCOUNT_NAMESPACE $NETWORKING_NAME -o jsonpath='{.spec.cidrBlock}')
        
        # Get subnet IDs
        PRIVATE_SUBNET_A_ID=$(kubectl get subnets -A -l crossplane.io/claim-namespace=$ACCOUNT_NAMESPACE,type=private,zone=a -o jsonpath='{.items[0].status.atProvider.subnetId}')
        PRIVATE_SUBNET_B_ID=$(kubectl get subnets -A -l crossplane.io/claim-namespace=$ACCOUNT_NAMESPACE,type=private,zone=b -o jsonpath='{.items[0].status.atProvider.subnetId}')
        PRIVATE_SUBNET_C_ID=$(kubectl get subnets -A -l crossplane.io/claim-namespace=$ACCOUNT_NAMESPACE,type=private,zone=c -o jsonpath='{.items[0].status.atProvider.subnetId}')
        
        PUBLIC_SUBNET_A_ID=$(kubectl get subnets -A -l crossplane.io/claim-namespace=$ACCOUNT_NAMESPACE,type=public,zone=a -o jsonpath='{.items[0].status.atProvider.subnetId}')
        PUBLIC_SUBNET_B_ID=$(kubectl get subnets -A -l crossplane.io/claim-namespace=$ACCOUNT_NAMESPACE,type=public,zone=b -o jsonpath='{.items[0].status.atProvider.subnetId}')
        PUBLIC_SUBNET_C_ID=$(kubectl get subnets -A -l crossplane.io/claim-namespace=$ACCOUNT_NAMESPACE,type=public,zone=c -o jsonpath='{.items[0].status.atProvider.subnetId}')
    else
        print_error "No VPC found named $NETWORKING_NAME"
        exit 1
    fi
else
    # Get from ConfigMap
    VPC_ID=$(kubectl get configmap -n $ACCOUNT_NAMESPACE ${NETWORKING_NAME}-networking -o jsonpath='{.data.VPC_ID}')
    VPC_CIDR=$(kubectl get configmap -n $ACCOUNT_NAMESPACE ${NETWORKING_NAME}-networking -o jsonpath='{.data.VPC_CIDR}')
    PRIVATE_SUBNET_A_ID=$(kubectl get configmap -n $ACCOUNT_NAMESPACE ${NETWORKING_NAME}-networking -o jsonpath='{.data.PRIVATE_SUBNET_A_ID}')
    PRIVATE_SUBNET_B_ID=$(kubectl get configmap -n $ACCOUNT_NAMESPACE ${NETWORKING_NAME}-networking -o jsonpath='{.data.PRIVATE_SUBNET_B_ID}')
    PRIVATE_SUBNET_C_ID=$(kubectl get configmap -n $ACCOUNT_NAMESPACE ${NETWORKING_NAME}-networking -o jsonpath='{.data.PRIVATE_SUBNET_C_ID}')
    PUBLIC_SUBNET_A_ID=$(kubectl get configmap -n $ACCOUNT_NAMESPACE ${NETWORKING_NAME}-networking -o jsonpath='{.data.PUBLIC_SUBNET_A_ID}')
    PUBLIC_SUBNET_B_ID=$(kubectl get configmap -n $ACCOUNT_NAMESPACE ${NETWORKING_NAME}-networking -o jsonpath='{.data.PUBLIC_SUBNET_B_ID}')
    PUBLIC_SUBNET_C_ID=$(kubectl get configmap -n $ACCOUNT_NAMESPACE ${NETWORKING_NAME}-networking -o jsonpath='{.data.PUBLIC_SUBNET_C_ID}')
fi

print_info "VPC ID: $VPC_ID"
print_info "VPC CIDR: $VPC_CIDR"

# Output the values as key=value pairs for configMapGenerator
cat <<EOF
CLUSTER_NAME=$CLUSTER_NAME
ACCOUNT_ALIAS=$ACCOUNT_ALIAS
ACCOUNT_ID=$ACCOUNT_ID
ACCOUNT_NAMESPACE=$ACCOUNT_NAMESPACE
ENVIRONMENT=$ENVIRONMENT
REGION=$REGION
VPC_ID=$VPC_ID
VPC_CIDR=$VPC_CIDR
PRIVATE_SUBNET_A_ID=$PRIVATE_SUBNET_A_ID
PRIVATE_SUBNET_B_ID=$PRIVATE_SUBNET_B_ID
PRIVATE_SUBNET_C_ID=$PRIVATE_SUBNET_C_ID
PUBLIC_SUBNET_A_ID=$PUBLIC_SUBNET_A_ID
PUBLIC_SUBNET_B_ID=$PUBLIC_SUBNET_B_ID
PUBLIC_SUBNET_C_ID=$PUBLIC_SUBNET_C_ID
EOF