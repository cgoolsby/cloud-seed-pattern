#!/bin/bash
set -euo pipefail

# Default values
GITHUB_OWNER="cgoolsby"
REPO_NAME="cloud-seed-pattern"
BRANCH="main"
CLUSTER_NAME=""
CLUSTER_TYPE="managed"  # Default to managed cluster
GITHUB_TOKEN=${GITHUB_TOKEN:-""}

# Help message
usage() {
    echo "Usage: $0 -c cluster_name [-t github_token] [-o github_owner] [-r repo_name] [-b branch] [-m]"
    echo
    echo "Bootstrap Flux on a Kubernetes cluster"
    echo
    echo "Required Options:"
    echo "  -c    Cluster name (e.g., 'management', 'dev-cluster')"
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
while getopts "c:t:o:r:b:mh" opt; do
    case $opt in
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

# Check required arguments
if [ -z "$CLUSTER_NAME" ]; then
    echo "Error: Cluster name is required (-c flag)"
    usage
fi

# Set Flux path based on cluster type
FLUX_PATH="clusters/$CLUSTER_NAME"

# Check if GITHUB_TOKEN is set
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GitHub token is required. Either set GITHUB_TOKEN environment variable or use -t flag."
    echo 'Error: Example "export GITHUB_TOKEN=$(gh auth token)"'
    exit 1
fi

# Check if kubectl is configured
if ! kubectl cluster-info &>/dev/null; then
    echo "Error: kubectl is not configured or cluster is not accessible"
    exit 1
fi

echo "🔄 Checking Flux CLI installation..."
if ! command -v flux &>/dev/null; then
    echo "⚠️  Flux CLI not found. Installing..."
    brew install fluxcd/tap/flux
fi

echo "🏗️  Setting up cluster directory structure..."
if [ ! -d "$FLUX_PATH" ]; then
    echo "   Creating cluster directory: $FLUX_PATH"
    mkdir -p "$FLUX_PATH"
    
    if [ "$CLUSTER_TYPE" = "management" ]; then
        echo "   Setting up management cluster components..."
        # Create kustomization that includes management components
        cat > "$FLUX_PATH/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - flux-system  # Flux components
  - crossplane   # Crossplane for infrastructure provisioning
  - cluster-api  # Cluster API for cluster management
EOF
        
        # Create flux-system kustomization
        mkdir -p "$FLUX_PATH/flux-system"
        cat > "$FLUX_PATH/flux-system/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../components/helmrelease/flux-system
EOF
        
        # Create crossplane kustomization
        mkdir -p "$FLUX_PATH/crossplane"
        cat > "$FLUX_PATH/crossplane/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../components/helmrelease/crossplane
EOF
        
        # Create cluster-api kustomization
        mkdir -p "$FLUX_PATH/cluster-api"
        cat > "$FLUX_PATH/cluster-api/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../components/helmrelease/cluster-api
EOF
    else
        echo "   Setting up managed cluster components..."
        # Create kustomization for managed cluster
        cat > "$FLUX_PATH/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - flux-system  # Flux components only
  # Additional workload components can be added here
EOF
        
        # Create flux-system kustomization
        mkdir -p "$FLUX_PATH/flux-system"
        cat > "$FLUX_PATH/flux-system/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../components/helmrelease/flux-system
EOF
    fi
    
    echo "   Committing cluster configuration..."
    git add "$FLUX_PATH"
    git commit -m "Add $CLUSTER_TYPE cluster configuration for $CLUSTER_NAME"
    git push origin "$BRANCH"
fi

echo "🧹 Cleaning up any existing Flux installation..."
flux uninstall --keep-namespace --silent || true

echo "🚀 Bootstrapping Flux for $CLUSTER_TYPE cluster: $CLUSTER_NAME..."
flux bootstrap github \
    --owner="$GITHUB_OWNER" \
    --repository="$REPO_NAME" \
    --branch="$BRANCH" \
    --path="$FLUX_PATH" \
    --personal \
    --token-auth \
    --components-extra=image-reflector-controller,image-automation-controller

echo "⏳ Waiting for Flux controllers to be ready..."
kubectl -n flux-system wait --for=condition=ready pod --all --timeout=2m

echo "✅ Flux bootstrap completed successfully for $CLUSTER_TYPE cluster: $CLUSTER_NAME!"
echo "📊 Checking Flux system health..."
flux check

echo "🔍 Current Flux resources:"
flux get all -A
