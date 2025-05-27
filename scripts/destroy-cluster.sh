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
if [ $# -lt 1 ]; then
    print_error "Insufficient arguments"
    echo "Usage: $0 <cluster-name> [cluster-namespace]"
    echo "Example: $0 my-cluster"
    echo "Example: $0 my-cluster custom-namespace"
    exit 1
fi

CLUSTER_NAME=$1
CLUSTER_NAMESPACE=${2:-default}

print_step "Destroying EKS cluster: $CLUSTER_NAME"
print_info "Cluster namespace: $CLUSTER_NAMESPACE"

# Step 1: Check if cluster exists
if ! kubectl get cluster -n $CLUSTER_NAMESPACE $CLUSTER_NAME &>/dev/null; then
    print_error "Cluster $CLUSTER_NAME not found in namespace $CLUSTER_NAMESPACE"
    exit 1
fi

# Step 2: Get cluster information
ACCOUNT_ALIAS=$(kubectl get cluster -n $CLUSTER_NAMESPACE $CLUSTER_NAME -o jsonpath='{.metadata.labels.account\.aws/alias}')
print_info "Account: $ACCOUNT_ALIAS"

# Step 3: Confirm deletion
echo ""
print_warning "This will permanently delete the EKS cluster and all its resources!"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    print_info "Deletion cancelled"
    exit 0
fi

# Step 4: Delete cluster resources
print_step "Deleting cluster resources..."

# Delete in reverse order of creation
print_info "Deleting machine pools..."
kubectl delete awsmanagedmachinepool -n $CLUSTER_NAMESPACE $CLUSTER_NAME-pool-0 --ignore-not-found=true

print_info "Deleting machine pool..."
kubectl delete machinepool -n $CLUSTER_NAMESPACE $CLUSTER_NAME-pool-0 --ignore-not-found=true

print_info "Deleting control plane..."
kubectl delete awsmanagedcontrolplane -n $CLUSTER_NAMESPACE $CLUSTER_NAME-control-plane --ignore-not-found=true

print_info "Deleting cluster..."
kubectl delete cluster -n $CLUSTER_NAMESPACE $CLUSTER_NAME --ignore-not-found=true

# Step 5: Wait for deletion to complete
print_step "Waiting for resources to be deleted..."
echo "This may take 10-15 minutes as AWS cleans up the EKS cluster..."

# Wait for cluster to be gone
while kubectl get cluster -n $CLUSTER_NAMESPACE $CLUSTER_NAME &>/dev/null; do
    echo -n "."
    sleep 10
done
echo ""

print_step "Cluster deletion complete!"

# Step 6: Clean up any remaining secrets
print_info "Cleaning up kubeconfig secret..."
kubectl delete secret -n $CLUSTER_NAMESPACE $CLUSTER_NAME-kubeconfig --ignore-not-found=true

# Step 7: If using GitOps, remind about removing from Git
if [ -d "kubernetes/clusters/$ACCOUNT_ALIAS" ]; then
    print_warning "Don't forget to remove cluster configuration from Git:"
    echo "  rm -rf kubernetes/clusters/$ACCOUNT_ALIAS/$CLUSTER_NAME"
    echo "  git add -A && git commit -m 'Remove $CLUSTER_NAME cluster configuration'"
    echo "  git push"
fi

print_step "Cluster $CLUSTER_NAME has been destroyed successfully!"