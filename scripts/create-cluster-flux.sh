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
    echo "Usage: $0 <account-alias> <cluster-name> [options]"
    echo ""
    echo "Options (as KEY=VALUE pairs):"
    echo "  NODE_INSTANCE_TYPE=t3.large"
    echo "  NODE_MIN_SIZE=3"
    echo "  NODE_MAX_SIZE=10"
    echo "  NODE_DESIRED_SIZE=5"
    echo "  EKS_VERSION=v1.29"
    echo "  CLUSTER_NAMESPACE=custom-namespace"
    echo ""
    echo "Example: $0 test-account-1 prod-cluster NODE_INSTANCE_TYPE=t3.large NODE_DESIRED_SIZE=5"
    exit 1
fi

ACCOUNT_ALIAS=$1
CLUSTER_NAME=$2
CLUSTER_DIR="kubernetes/environments/$ACCOUNT_ALIAS/clusters/$CLUSTER_NAME"

# Shift to process additional arguments
shift 2

print_step "Creating Flux-managed EKS cluster: $CLUSTER_NAME"
print_info "Account: $ACCOUNT_ALIAS"
print_info "Directory: $CLUSTER_DIR"

# Check if environment exists
if [ ! -d "kubernetes/environments/$ACCOUNT_ALIAS" ]; then
    print_error "Environment directory not found: kubernetes/environments/$ACCOUNT_ALIAS"
    print_warning "Please run ./scripts/gitops-account-setup.sh $ACCOUNT_ALIAS first"
    exit 1
fi

# Check if cluster-values ConfigMap exists
if [ ! -f "kubernetes/environments/$ACCOUNT_ALIAS/cluster-values.yaml" ]; then
    print_warning "cluster-values.yaml not found. Generating it now..."
    ./scripts/update-cluster-values.sh "$ACCOUNT_ALIAS"
fi

# Create cluster directory
print_step "Creating cluster directory..."
mkdir -p "$CLUSTER_DIR"

# Build literals array for configMapGenerator
LITERALS=(
    "CLUSTER_NAME=$CLUSTER_NAME"
)

# Process additional arguments
for arg in "$@"; do
    if [[ "$arg" =~ ^[A-Z_]+=.+$ ]]; then
        LITERALS+=("$arg")
        print_info "Override: $arg"
    else
        print_warning "Ignoring invalid argument: $arg (expected KEY=VALUE)"
    fi
done

# Set default namespace if not provided
if ! printf '%s\n' "${LITERALS[@]}" | grep -q "^CLUSTER_NAMESPACE="; then
    LITERALS+=("CLUSTER_NAMESPACE=default")
fi

# Create kustomization.yaml
print_step "Creating kustomization.yaml..."
cat > "$CLUSTER_DIR/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../../../base/cluster-templates/eks-cluster.yaml

configMapGenerator:
  - name: $CLUSTER_NAME-values
    namespace: flux-system
    literals:
EOF

# Add literals to the file
for literal in "${LITERALS[@]}"; do
    echo "      - $literal" >> "$CLUSTER_DIR/kustomization.yaml"
done

# Create flux-kustomization.yaml
print_step "Creating flux-kustomization.yaml..."
cat > "$CLUSTER_DIR/flux-kustomization.yaml" <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster-$CLUSTER_NAME-$ACCOUNT_ALIAS
  namespace: flux-system
spec:
  interval: 5m0s
  path: ./$CLUSTER_DIR
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: env-$ACCOUNT_ALIAS  # Wait for environment setup
  postBuild:
    substituteFrom:
      # Environment-wide values (VPC, subnets, etc.)
      - kind: ConfigMap
        name: cluster-values
      # Cluster-specific values
      - kind: ConfigMap
        name: $CLUSTER_NAME-values
  wait: false
  timeout: 60m0s
EOF

print_step "Cluster configuration created!"

# Show what was created
echo ""
echo "Created files:"
echo "  - $CLUSTER_DIR/kustomization.yaml"
echo "  - $CLUSTER_DIR/flux-kustomization.yaml"
echo ""
echo "Configuration:"
for literal in "${LITERALS[@]}"; do
    echo "  - $literal"
done

# Provide next steps
echo ""
print_step "Next steps:"
echo ""
echo "1. Review the configuration:"
echo "   cat $CLUSTER_DIR/kustomization.yaml"
echo ""
echo "2. Apply cluster-values ConfigMap (if not already done):"
echo "   kubectl apply -f kubernetes/environments/$ACCOUNT_ALIAS/cluster-values.yaml"
echo ""
echo "3. Deploy the cluster:"
echo "   kubectl apply -f $CLUSTER_DIR/flux-kustomization.yaml"
echo ""
echo "   Or commit and push for GitOps deployment:"
echo "   git add $CLUSTER_DIR"
echo "   git commit -m \"Add $CLUSTER_NAME cluster\""
echo "   git push"
echo ""
echo "4. Monitor cluster creation:"
echo "   flux get kustomization cluster-$CLUSTER_NAME-$ACCOUNT_ALIAS --watch"
echo "   kubectl get cluster $CLUSTER_NAME -w"
echo ""
echo "5. Get kubeconfig when ready:"
echo "   kubectl get secret $CLUSTER_NAME-kubeconfig -o jsonpath='{.data.value}' | base64 -d > $CLUSTER_NAME.kubeconfig"