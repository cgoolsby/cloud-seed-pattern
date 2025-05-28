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
CLUSTER_DIR="$ENVIRONMENT_DIR/clusters/$CLUSTER_NAME"
TEMPLATE_DIR="kubernetes/base/cluster-templates"

print_step "Creating GitOps configuration for EKS cluster: $CLUSTER_NAME"
print_info "Account: $ACCOUNT_ALIAS"
print_info "Cluster namespace: $CLUSTER_NAMESPACE"
print_info "Target directory: $CLUSTER_DIR"

# Step 1: Verify environment directory exists
if [ ! -d "$ENVIRONMENT_DIR" ]; then
    print_error "Environment directory $ENVIRONMENT_DIR not found!"
    print_warning "Please run ./scripts/gitops-account-setup.sh $ACCOUNT_ALIAS first"
    exit 1
fi

# Step 2: Check if cluster directory already exists
if [ -d "$CLUSTER_DIR" ]; then
    print_error "Cluster directory $CLUSTER_DIR already exists!"
    print_warning "Please choose a different cluster name or remove the existing directory"
    exit 1
fi

# Step 3: Verify required ConfigMaps exist in the account namespace
print_step "Verifying account configuration..."
if ! kubectl get namespace $ACCOUNT_NAMESPACE &>/dev/null; then
    print_error "Account namespace $ACCOUNT_NAMESPACE not found!"
    print_warning "Please ensure the account has been properly set up with Flux"
    exit 1
fi

# Check for account-info ConfigMap
if ! kubectl get configmap -n $ACCOUNT_NAMESPACE account-info &>/dev/null; then
    print_error "ConfigMap account-info not found in namespace $ACCOUNT_NAMESPACE"
    exit 1
fi

# Check for networking values ConfigMap
if ! kubectl get configmap -n $ACCOUNT_NAMESPACE main-networking &>/dev/null; then
    print_error "ConfigMap main-networking not found in namespace $ACCOUNT_NAMESPACE"
    print_warning "Please ensure networking has been provisioned for this account"
    exit 1
fi

# Step 4: Create cluster directory
print_step "Creating cluster directory structure..."
mkdir -p "$CLUSTER_DIR"

# Step 5: Create cluster-specific values ConfigMap
print_step "Creating cluster values ConfigMap..."
cat > "$CLUSTER_DIR/cluster-values.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${CLUSTER_NAME}-values
  namespace: ${ACCOUNT_NAMESPACE}
data:
  CLUSTER_NAME: "${CLUSTER_NAME}"
  CLUSTER_NAMESPACE: "${CLUSTER_NAMESPACE}"
  NODEGROUP_NAME: "${CLUSTER_NAME}-ng-0"
  MACHINE_POOL_NAME: "${CLUSTER_NAME}-pool-0"
  MIN_SIZE: "1"
  MAX_SIZE: "3"
  INSTANCE_TYPE: "t3.medium"
EOF

# Step 6: Create Kustomization that references the base template
print_step "Creating cluster Kustomization..."
cat > "$CLUSTER_DIR/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - cluster-values.yaml
  - ../../../../../../base/cluster-templates/eks-cluster.yaml

# These labels will be added to all resources
commonLabels:
  cluster.x-k8s.io/cluster-name: ${CLUSTER_NAME}
  account.aws/alias: ${ACCOUNT_ALIAS}
  managed-by: flux

# Set the namespace for all resources
namespace: ${CLUSTER_NAMESPACE}
EOF

# Step 7: Create Flux Kustomization
print_step "Creating Flux Kustomization..."
cat > "$CLUSTER_DIR/flux-kustomization.yaml" <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ${CLUSTER_NAME}
  namespace: ${ACCOUNT_NAMESPACE}
spec:
  interval: 5m
  path: ./kubernetes/environments/${ACCOUNT_ALIAS}/clusters/${CLUSTER_NAME}
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: account-info
      - kind: ConfigMap
        name: main-networking
      - kind: ConfigMap
        name: ${CLUSTER_NAME}-values
  dependsOn:
    - name: main-networking
      namespace: ${ACCOUNT_NAMESPACE}
  healthChecks:
    - apiVersion: cluster.x-k8s.io/v1beta1
      kind: Cluster
      name: ${CLUSTER_NAME}
      namespace: ${CLUSTER_NAMESPACE}
EOF

# Step 8: Update parent clusters kustomization to include new cluster
print_step "Updating clusters kustomization..."
CLUSTERS_KUSTOMIZATION="$ENVIRONMENT_DIR/clusters/kustomization.yaml"

# Check if the clusters directory has a kustomization.yaml
if [ ! -f "$CLUSTERS_KUSTOMIZATION" ]; then
    print_info "Creating clusters kustomization.yaml..."
    cat > "$CLUSTERS_KUSTOMIZATION" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ${CLUSTER_NAME}/flux-kustomization.yaml
EOF
else
    # Add the new cluster to existing kustomization
    if ! grep -q "$CLUSTER_NAME/flux-kustomization.yaml" "$CLUSTERS_KUSTOMIZATION"; then
        print_info "Adding cluster to clusters kustomization..."
        # Use sed to add the new resource
        sed -i '' "/^resources:/a\\
  - ${CLUSTER_NAME}/flux-kustomization.yaml
" "$CLUSTERS_KUSTOMIZATION"
    fi
fi

# Step 9: Create a branch for the PR
BRANCH_NAME="create-cluster-${CLUSTER_NAME}-$(date +%Y%m%d-%H%M%S)"
print_step "Creating branch: $BRANCH_NAME"
git checkout -b "$BRANCH_NAME"

# Step 10: Stage and commit the changes
print_step "Committing changes..."
git add "$CLUSTER_DIR"
git add "$CLUSTERS_KUSTOMIZATION"

git commit -m "Add EKS cluster: $CLUSTER_NAME in $ACCOUNT_ALIAS

- Created cluster configuration using eks-cluster template
- Added Flux Kustomization for GitOps management
- Cluster will be deployed to namespace: $CLUSTER_NAMESPACE
- Instance type: t3.medium with 1-3 nodes

🤖 Generated with gitops-create-cluster.sh"

# Step 11: Provide next steps
print_step "GitOps configuration created successfully!"
echo ""
echo "Next steps:"
echo "1. Review the generated files:"
echo "   - $CLUSTER_DIR/cluster-values.yaml"
echo "   - $CLUSTER_DIR/kustomization.yaml"
echo "   - $CLUSTER_DIR/flux-kustomization.yaml"
echo ""
echo "2. Push the branch and create a PR:"
echo "   git push origin $BRANCH_NAME"
echo "   gh pr create --title \"Add EKS cluster: $CLUSTER_NAME\" --body \"Creates new EKS cluster in $ACCOUNT_ALIAS account\""
echo ""
echo "3. After PR is merged, Flux will automatically:"
echo "   - Create the cluster in namespace $CLUSTER_NAMESPACE"
echo "   - Monitor its health"
echo "   - Report status in the Flux Kustomization"
echo ""
echo "4. Monitor deployment:"
echo "   flux get kustomization -n $ACCOUNT_NAMESPACE $CLUSTER_NAME"
echo "   kubectl get cluster -n $CLUSTER_NAMESPACE $CLUSTER_NAME"
echo ""
echo "5. Get kubeconfig once ready:"
echo "   kubectl get secret -n $CLUSTER_NAMESPACE $CLUSTER_NAME-kubeconfig -o jsonpath='{.data.value}' | base64 -d > $CLUSTER_NAME.kubeconfig"