#!/bin/bash
set -euo pipefail

# bootstrap-flux.sh - Bootstrap Flux on a Kubernetes cluster

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source common functions
source "${SCRIPT_DIR}/common.sh"

# Script-specific defaults
GITHUB_OWNER="${DEFAULT_GITHUB_OWNER}"
REPO_NAME="${DEFAULT_REPO_NAME}"
BRANCH="${DEFAULT_BRANCH}"
ACCOUNT_NAME=""
CLUSTER_NAME=""
CLUSTER_TYPE="managed"  # Default to managed cluster
GITHUB_TOKEN=${GITHUB_TOKEN:-""}

# Help message
usage() {
    echo "Usage: $0 -a account_name -c cluster_name [-t github_token] [-o github_owner] [-r repo_name] [-b branch] [-m]"
    echo
    echo "Bootstrap Flux on a Kubernetes cluster"
    echo
    echo "Required Options:"
    echo "  -a    Account name (e.g., 'management', 'dev-account', 'prod-account')"
    echo "  -c    Cluster name (e.g., 'primary', 'dev-cluster')"
    echo
    echo "Options:"
    echo "  -m    Bootstrap as management cluster (includes Crossplane & Cluster API)"
    echo "  -t    GitHub personal access token (required if GITHUB_TOKEN env var is not set)"
    echo "  -o    GitHub owner/organization (default: $GITHUB_OWNER)"
    echo "  -r    Repository name (default: $REPO_NAME)"
    echo "  -b    Branch name (default: $BRANCH)"
    echo "  -h    Show this help message"
    exit 1
}

# Parse command line arguments
while getopts "a:c:t:o:r:b:mh" opt; do
    case $opt in
        a) ACCOUNT_NAME="$OPTARG" ;;
        c) CLUSTER_NAME="$OPTARG" ;;
        t) GITHUB_TOKEN="$OPTARG" ;;
        o) GITHUB_OWNER="$OPTARG" ;;
        r) REPO_NAME="$OPTARG" ;;
        b) BRANCH="$OPTARG" ;;
        m) CLUSTER_TYPE="management" ;;
        h) usage ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    esac
done

# Validate inputs
if [ -z "$ACCOUNT_NAME" ]; then
    print_error "Account name is required (-a flag)"
    usage
fi

if [ -z "$CLUSTER_NAME" ]; then
    print_error "Cluster name is required (-c flag)"
    usage
fi

if ! validate_account_name "$ACCOUNT_NAME"; then
    exit 1
fi

if ! validate_cluster_name "$CLUSTER_NAME"; then
    exit 1
fi

# Set Flux path based on account and cluster
FLUX_PATH="clusters/$ACCOUNT_NAME/$CLUSTER_NAME"

# Check if GITHUB_TOKEN is set
if [ -z "$GITHUB_TOKEN" ]; then
    print_error "GitHub token is required. Either set GITHUB_TOKEN environment variable or use -t flag."
    print_info 'Example: export GITHUB_TOKEN=$(gh auth token)'
    exit 1
fi

# Check required tools
if ! check_required_tools; then
    exit 1
fi

if ! check_kubectl; then
    exit 1
fi

print_status "Checking Flux CLI installation..."
if ! check_flux; then
    print_info "Installing Flux CLI..."
    brew install fluxcd/tap/flux
fi

print_status "Setting up cluster directory structure..."
if [ ! -d "$FLUX_PATH" ]; then
    print_info "Creating cluster directory: $FLUX_PATH"
    mkdir -p "$FLUX_PATH"
    
    # Create account-level kustomization if it doesn't exist
    ACCOUNT_PATH="clusters/$ACCOUNT_NAME"
    if [ ! -f "$ACCOUNT_PATH/kustomization.yaml" ]; then
        print_info "Creating account kustomization for $ACCOUNT_NAME"
        cat > "$ACCOUNT_PATH/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: aws-$ACCOUNT_NAME

resources:
  # Clusters will be added here
  - $CLUSTER_NAME
EOF
    else
        # Add cluster to existing account kustomization if not already present
        if ! grep -q "  - $CLUSTER_NAME" "$ACCOUNT_PATH/kustomization.yaml"; then
            print_info "Adding $CLUSTER_NAME to account kustomization"
            sed -i.bak "/resources:/a\\  - $CLUSTER_NAME" "$ACCOUNT_PATH/kustomization.yaml"
            rm "$ACCOUNT_PATH/kustomization.yaml.bak"
        fi
    fi
    
    # Always start with system template as base
    print_info "Setting up base system components from template..."
    cp -r clusters/_template/system/* "$FLUX_PATH/"
    
    # Replace placeholders in all yaml files
    print_info "Updating paths with account and cluster names..."
    find "$FLUX_PATH" -name "*.yaml" -type f -exec sed -i.bak \
        -e "s|ACCOUNT_NAME|$ACCOUNT_NAME|g" \
        -e "s|CLUSTER_NAME|$CLUSTER_NAME|g" {} \;
    # Remove backup files
    find "$FLUX_PATH" -name "*.yaml.bak" -type f -delete
    
    if [ "$CLUSTER_TYPE" = "management" ]; then
        print_info "Adding management cluster components..."
        # Copy management-specific components (crossplane and cluster-api)
        cp -r clusters/_template/management/crossplane* "$FLUX_PATH/"
        cp -r clusters/_template/management/cluster-api* "$FLUX_PATH/"
        
        # Replace placeholders in the newly copied management files
        find "$FLUX_PATH" -name "*.yaml" -type f -exec sed -i.bak \
            -e "s|ACCOUNT_NAME|$ACCOUNT_NAME|g" \
            -e "s|CLUSTER_NAME|$CLUSTER_NAME|g" {} \;
        # Remove backup files
        find "$FLUX_PATH" -name "*.yaml.bak" -type f -delete
        
        # Add management components to kustomization.yaml using yq
        if ! command -v yq &>/dev/null; then
            print_error "yq is required for management clusters but not found in PATH"
            print_info "Please install yq: brew install yq"
            exit 1
        fi
        yq eval -i '.resources += ["crossplane.yaml", "cluster-api.yaml"]' "$FLUX_PATH/kustomization.yaml"
    fi
    
    print_info "Committing cluster configuration..."
    safe_git_add "clusters/$ACCOUNT_NAME"
    safe_git_commit "Add $CLUSTER_TYPE cluster configuration for $ACCOUNT_NAME/$CLUSTER_NAME"
    git push origin "$BRANCH"
fi

print_status "Cleaning up any existing Flux installation..."
# Delete the flux-system kustomization if it exists to avoid path conflicts
kubectl delete kustomization flux-system -n flux-system --ignore-not-found=true || true
flux uninstall --keep-namespace --silent || true

print_status "Bootstrapping Flux for $CLUSTER_TYPE cluster: $ACCOUNT_NAME/$CLUSTER_NAME..."
flux bootstrap github \
    --owner="$GITHUB_OWNER" \
    --repository="$REPO_NAME" \
    --branch="$BRANCH" \
    --path="$FLUX_PATH" \
    --personal \
    --token-auth \
    --components-extra=image-reflector-controller,image-automation-controller

print_status "Waiting for Flux controllers to be ready..."
kubectl -n flux-system wait --for=condition=ready pod --all --timeout=2m

print_success "Flux bootstrap completed successfully for $CLUSTER_TYPE cluster: $ACCOUNT_NAME/$CLUSTER_NAME!"
print_info "Checking Flux system health..."
flux check

print_info "Current Flux resources:"
flux get all -A
