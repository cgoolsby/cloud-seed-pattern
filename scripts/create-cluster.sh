#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_info() {
    echo -e "${BLUE}Info: $1${NC}"
}

# Check arguments
if [ $# -lt 2 ]; then
    print_error "Insufficient arguments"
    echo "Usage: $0 <account-alias> <cluster-name> [cluster-namespace]"
    echo "Example: $0 demo-prod my-cluster"
    echo "Example: $0 demo-prod my-cluster custom-namespace"
    exit 1
fi

ACCOUNT_ALIAS=$1
CLUSTER_NAME=$2
CLUSTER_NAMESPACE=${3:-default}
ACCOUNT_NAMESPACE="aws-$ACCOUNT_ALIAS"
ENVIRONMENT_DIR="kubernetes/environments/$ACCOUNT_ALIAS"

print_step "Creating EKS cluster: $CLUSTER_NAME"
print_info "Account: $ACCOUNT_ALIAS"
print_info "Cluster namespace: $CLUSTER_NAMESPACE"

# Step 1: Verify account namespace exists
if ! kubectl get namespace $ACCOUNT_NAMESPACE &>/dev/null; then
    print_error "Account namespace $ACCOUNT_NAMESPACE not found!"
    print_warning "Please run ./scripts/create-account-resources.sh $ACCOUNT_ALIAS first"
    exit 1
fi

# Step 2: Get account information
ACCOUNT_ID=$(kubectl get configmap -n $ACCOUNT_NAMESPACE account-info -o jsonpath='{.data.ACCOUNT_ID}')
ACCOUNT_ENV=$(kubectl get configmap -n $ACCOUNT_NAMESPACE account-info -o jsonpath='{.data.ENVIRONMENT}')

print_info "Account ID: $ACCOUNT_ID"
print_info "Environment: $ACCOUNT_ENV"

# Step 3: Check if VPC is ready
print_step "Checking VPC status..."
VPC_STATUS=$(kubectl get vpc.network.example.org -n $ACCOUNT_NAMESPACE main -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
if [ "$VPC_STATUS" != "True" ]; then
    print_error "VPC is not ready in namespace $ACCOUNT_NAMESPACE"
    print_warning "Please wait for VPC to be ready: kubectl get vpc.network.example.org -n $ACCOUNT_NAMESPACE main"
    exit 1
fi

VPC_ID=$(kubectl get vpc.network.example.org -n $ACCOUNT_NAMESPACE main -o jsonpath='{.status.vpcId}')
print_info "Using VPC: $VPC_ID"

# Step 4: Get subnet IDs
print_step "Getting subnet information..."
# Get private subnet IDs from the actual subnet resources
PRIVATE_SUBNET_IDS=$(kubectl get subnets -A -l crossplane.io/claim-namespace=$ACCOUNT_NAMESPACE,type=private -o jsonpath='{.items[*].status.atProvider.subnetId}')
PUBLIC_SUBNET_IDS=$(kubectl get subnets -A -l crossplane.io/claim-namespace=$ACCOUNT_NAMESPACE,type=public -o jsonpath='{.items[*].status.atProvider.subnetId}')

if [ -z "$PRIVATE_SUBNET_IDS" ]; then
    print_error "No private subnets found for account $ACCOUNT_ALIAS"
    exit 1
fi

# Convert space-separated list to array
IFS=' ' read -r -a PRIVATE_SUBNET_ARRAY <<< "$PRIVATE_SUBNET_IDS"
IFS=' ' read -r -a PUBLIC_SUBNET_ARRAY <<< "$PUBLIC_SUBNET_IDS"

print_info "Found ${#PRIVATE_SUBNET_ARRAY[@]} private subnets"
print_info "Found ${#PUBLIC_SUBNET_ARRAY[@]} public subnets"

# Step 5: Create cluster namespace if it doesn't exist
if [ "$CLUSTER_NAMESPACE" != "default" ]; then
    print_step "Creating cluster namespace: $CLUSTER_NAMESPACE"
    kubectl create namespace $CLUSTER_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
fi

# Step 6: Create the cluster manifest
print_step "Creating EKS cluster manifest..."
cat <<EOF | kubectl apply -f -
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: $CLUSTER_NAME
  namespace: $CLUSTER_NAMESPACE
  labels:
    cluster.x-k8s.io/cluster-name: $CLUSTER_NAME
    account.aws/alias: $ACCOUNT_ALIAS
    environment: $ACCOUNT_ENV
spec:
  clusterNetwork:
    pods:
      cidrBlocks:
        - 192.168.0.0/16
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta2
    kind: AWSManagedControlPlane
    name: $CLUSTER_NAME-control-plane
  infrastructureRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta2
    kind: AWSManagedControlPlane
    name: $CLUSTER_NAME-control-plane
---
apiVersion: controlplane.cluster.x-k8s.io/v1beta2
kind: AWSManagedControlPlane
metadata:
  name: $CLUSTER_NAME-control-plane
  namespace: $CLUSTER_NAMESPACE
spec:
  region: us-west-2
  version: "v1.28"
  roleName: eks-controlplane.cluster-api-provider-aws.sigs.k8s.io
  identityRef:
    kind: AWSClusterRoleIdentity
    name: $ACCOUNT_ALIAS-identity
  network:
    vpc:
      id: $VPC_ID
    subnets:
$(for subnet in "${PRIVATE_SUBNET_ARRAY[@]}"; do echo "      - id: $subnet"; done)
  associateOIDCProvider: true
  addons:
  - name: vpc-cni
    version: v1.16.0-eksbuild.1
  - name: coredns
    version: v1.10.1-eksbuild.6
  - name: kube-proxy
    version: v1.28.5-eksbuild.2
---
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachinePool
metadata:
  name: $CLUSTER_NAME-pool-0
  namespace: $CLUSTER_NAMESPACE
spec:
  clusterName: $CLUSTER_NAME
  replicas: 2
  template:
    spec:
      clusterName: $CLUSTER_NAME
      bootstrap:
        dataSecretName: ""
      infrastructureRef:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
        kind: AWSManagedMachinePool
        name: $CLUSTER_NAME-pool-0
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: AWSManagedMachinePool
metadata:
  name: $CLUSTER_NAME-pool-0
  namespace: $CLUSTER_NAMESPACE
spec:
  roleAdditionalPolicies:
    - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  roleName: eks-nodegroup.cluster-api-provider-aws.sigs.k8s.io
  scaling:
    minSize: 1
    maxSize: 3
  instanceType: t3.medium
  eksNodegroupName: $CLUSTER_NAME-ng-0
  subnetIDs:
$(for subnet in "${PRIVATE_SUBNET_ARRAY[@]}"; do echo "    - $subnet"; done)
EOF

# Step 7: Wait for cluster to start provisioning
print_step "Waiting for cluster to start provisioning..."
sleep 5

# Step 8: Check cluster status
kubectl get cluster -n $CLUSTER_NAMESPACE $CLUSTER_NAME

# Step 9: Provide status commands
print_step "Cluster creation initiated!"
echo ""
echo "Monitor cluster creation with:"
echo "  kubectl get cluster -n $CLUSTER_NAMESPACE $CLUSTER_NAME -w"
echo ""
echo "Check control plane status:"
echo "  kubectl describe awsmanagedcontrolplane -n $CLUSTER_NAMESPACE $CLUSTER_NAME-control-plane"
echo ""
echo "Check machine pool status:"
echo "  kubectl describe awsmanagedmachinepool -n $CLUSTER_NAMESPACE $CLUSTER_NAME-pool-0"
echo ""
echo "Get kubeconfig once ready:"
echo "  kubectl get secret -n $CLUSTER_NAMESPACE $CLUSTER_NAME-kubeconfig -o jsonpath='{.data.value}' | base64 -d > $CLUSTER_NAME.kubeconfig"
echo "  export KUBECONFIG=\$PWD/$CLUSTER_NAME.kubeconfig"
echo ""
echo "To make this cluster GitOps managed:"
echo "  1. Save the cluster manifest to: $ENVIRONMENT_DIR/clusters/$CLUSTER_NAME/"
echo "  2. Update $ENVIRONMENT_DIR/clusters/kustomization.yaml"
echo "  3. Commit and push the changes"