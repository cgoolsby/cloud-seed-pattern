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
    echo "Usage: $0 <account-alias> <cluster-name>"
    echo "Example: $0 demo-prod my-cluster"
    exit 1
fi

ACCOUNT_ALIAS=$1
CLUSTER_NAME=$2
ENVIRONMENT_DIR="kubernetes/environments/$ACCOUNT_ALIAS"
CLUSTER_DIR="$ENVIRONMENT_DIR/clusters/$CLUSTER_NAME"
CLUSTERS_KUSTOMIZATION="$ENVIRONMENT_DIR/clusters/kustomization.yaml"

print_step "Creating GitOps configuration to destroy EKS cluster: $CLUSTER_NAME"
print_info "Account: $ACCOUNT_ALIAS"
print_info "Cluster directory: $CLUSTER_DIR"

# Step 1: Verify cluster directory exists
if [ ! -d "$CLUSTER_DIR" ]; then
    print_error "Cluster directory $CLUSTER_DIR not found!"
    print_warning "The cluster may have already been removed or doesn't exist"
    exit 1
fi

# Step 2: Create a branch for the PR
BRANCH_NAME="destroy-cluster-${CLUSTER_NAME}-$(date +%Y%m%d-%H%M%S)"
print_step "Creating branch: $BRANCH_NAME"
git checkout -b "$BRANCH_NAME"

# Step 3: Remove cluster from clusters kustomization
if [ -f "$CLUSTERS_KUSTOMIZATION" ]; then
    print_step "Removing cluster from clusters kustomization..."
    # Remove the line containing the cluster reference
    sed -i '' "/${CLUSTER_NAME}\/flux-kustomization.yaml/d" "$CLUSTERS_KUSTOMIZATION"
    
    # Check if resources section is now empty (only contains "resources:" and whitespace)
    if grep -q "^resources:" "$CLUSTERS_KUSTOMIZATION" && ! grep -q "^  - " "$CLUSTERS_KUSTOMIZATION"; then
        print_info "No more clusters in this environment, removing empty kustomization..."
        rm -f "$CLUSTERS_KUSTOMIZATION"
    fi
fi

# Step 4: Remove cluster directory
print_step "Removing cluster directory..."
rm -rf "$CLUSTER_DIR"

# Step 5: Stage and commit the changes
print_step "Committing changes..."
git add -A "$ENVIRONMENT_DIR/clusters/"

git commit -m "Remove EKS cluster: $CLUSTER_NAME from $ACCOUNT_ALIAS

- Removed cluster configuration and Flux Kustomization
- Flux will automatically delete the cluster and all its resources
- This is a destructive operation that cannot be undone

⚠️  WARNING: This will permanently delete the cluster and all workloads running on it

🤖 Generated with gitops-destroy-cluster.sh"

# Step 6: Provide next steps
print_step "GitOps configuration for cluster removal created successfully!"
echo ""
echo -e "${YELLOW}⚠️  WARNING: This will PERMANENTLY DELETE the cluster and all its resources!${NC}"
echo ""
echo "Next steps:"
echo "1. Review the changes:"
echo "   git diff HEAD~1"
echo ""
echo "2. Push the branch and create a PR:"
echo "   git push origin $BRANCH_NAME"
echo "   gh pr create --title \"Remove EKS cluster: $CLUSTER_NAME\" --body \"⚠️  Removes EKS cluster from $ACCOUNT_ALIAS account. This is a destructive operation.\""
echo ""
echo "3. After PR is merged, Flux will automatically:"
echo "   - Delete the cluster and all its resources"
echo "   - Remove the Flux Kustomization"
echo "   - Clean up all associated AWS resources"
echo ""
echo "4. Monitor deletion (before resources are gone):"
echo "   flux events --for Kustomization/$CLUSTER_NAME -n aws-$ACCOUNT_ALIAS"
echo "   kubectl get cluster -n \$(kubectl get cluster -A | grep $CLUSTER_NAME | awk '{print \$1}') $CLUSTER_NAME"
echo ""
echo -e "${RED}Make sure you have backed up any important data before merging the PR!${NC}"