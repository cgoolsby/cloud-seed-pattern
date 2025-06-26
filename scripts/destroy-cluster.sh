#!/bin/bash
set -euo pipefail

# destroy-cluster.sh - Destroy a Kubernetes cluster

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source common functions
source "${SCRIPT_DIR}/common.sh"

# Help message
usage() {
    cat << EOF
Usage: $0 <account-name> <cluster-name> [options]

Destroy a Kubernetes cluster in the specified account.

Arguments:
    account-name    Name of the AWS account
    cluster-name    Name of the cluster to destroy

Options:
    -f, --force       Skip confirmation prompts
    -k, --keep-config Keep the cluster configuration files (only remove from kustomization)
    -w, --wait        Wait for the cluster to be fully destroyed
    -t, --timeout     Timeout for waiting (default: 600s)
    -h, --help        Show this help message

Examples:
    # Destroy a cluster with confirmation
    $0 dev-account dev-cluster

    # Force destroy without confirmation
    $0 test-account test-cluster --force

    # Destroy cluster but keep configuration files
    $0 dev-account old-cluster --keep-config

    # Destroy and wait for completion
    $0 prod-account decom-cluster --wait --timeout 900

Warning:
    This operation will:
    - Remove the cluster from Flux management
    - Delete all cluster resources (VPC, subnets, EKS cluster, nodes, etc.)
    - Optionally remove the cluster configuration files
    
    This action cannot be undone!
EOF
    exit 1
}

# Parse arguments
if [[ $# -lt 2 ]]; then
    print_error "Missing required arguments"
    usage
fi

ACCOUNT_NAME="$1"
CLUSTER_NAME="$2"
shift 2

# Optional parameters
FORCE="false"
KEEP_CONFIG="false"
WAIT="false"
TIMEOUT="600"

# Parse optional arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE="true"
            shift
            ;;
        -k|--keep-config)
            KEEP_CONFIG="true"
            shift
            ;;
        -w|--wait)
            WAIT="true"
            shift
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate inputs
print_info "Validating inputs..."

if ! validate_account_name "$ACCOUNT_NAME"; then
    exit 1
fi

if ! validate_cluster_name "$CLUSTER_NAME"; then
    exit 1
fi

if ! account_exists "$ACCOUNT_NAME"; then
    print_error "Account not found: $ACCOUNT_NAME"
    exit 1
fi

if ! cluster_exists "$ACCOUNT_NAME" "$CLUSTER_NAME"; then
    print_error "Cluster not found: $ACCOUNT_NAME/$CLUSTER_NAME"
    exit 1
fi

# Check required tools
if ! check_required_tools; then
    exit 1
fi

if ! check_kubectl; then
    exit 1
fi

# Get cluster information
ACCOUNT_NAMESPACE=$(get_account_namespace "$ACCOUNT_NAME")
CLUSTER_DIR="${CLUSTERS_DIR}/${ACCOUNT_NAME}/${CLUSTER_NAME}"
ACCOUNT_DIR="${CLUSTERS_DIR}/${ACCOUNT_NAME}"

# Show cluster information
print_status "Cluster Information:"
echo "  Account: $ACCOUNT_NAME"
echo "  Cluster: $CLUSTER_NAME"
echo "  Namespace: $ACCOUNT_NAMESPACE"
echo "  Directory: $CLUSTER_DIR"

# Check if cluster resources exist
print_status "Checking cluster resources..."
CLUSTER_EXISTS="false"
if kubectl get cluster "$CLUSTER_NAME" -n "$ACCOUNT_NAMESPACE" &>/dev/null; then
    CLUSTER_EXISTS="true"
    print_info "Cluster API cluster found"
fi

# Check for Flux kustomization
FLUX_KUSTOMIZATION_EXISTS="false"
if kubectl get kustomization "$CLUSTER_NAME" -n flux-system &>/dev/null; then
    FLUX_KUSTOMIZATION_EXISTS="true"
    print_info "Flux kustomization found"
fi

# Confirm destruction
if [[ "$FORCE" != "true" ]]; then
    print_warning "   WARNING: This will DESTROY the cluster '$CLUSTER_NAME' in account '$ACCOUNT_NAME'"
    print_warning "   All resources will be permanently deleted!"
    echo
    read -p "Type the cluster name to confirm destruction: " -r
    if [[ "$REPLY" != "$CLUSTER_NAME" ]]; then
        print_error "Cluster name mismatch. Aborting."
        exit 1
    fi
    
    read -p "Are you absolutely sure? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled"
        exit 0
    fi
fi

# Step 1: Remove cluster from account kustomization
print_status "Removing cluster from account kustomization..."
ACCOUNT_KUSTOMIZATION="${ACCOUNT_DIR}/kustomization.yaml"

if [[ -f "$ACCOUNT_KUSTOMIZATION" ]]; then
    # Use yq if available, otherwise use sed
    if command -v yq &>/dev/null; then
        yq eval -i 'del(.resources[] | select(. == "'${CLUSTER_NAME}'"))' "$ACCOUNT_KUSTOMIZATION"
    else
        # Remove the line containing the cluster (macOS compatible)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' -e "/  - ${CLUSTER_NAME}/d" "$ACCOUNT_KUSTOMIZATION"
        else
            sed -i "/  - ${CLUSTER_NAME}/d" "$ACCOUNT_KUSTOMIZATION"
        fi
    fi
    print_success "Removed cluster from account kustomization"
fi

# Step 2: Remove or rename cluster directory
if [[ "$KEEP_CONFIG" == "true" ]]; then
    print_status "Keeping cluster configuration (disabled)..."
    # Rename the directory to mark it as disabled
    DISABLED_DIR="${CLUSTER_DIR}.disabled"
    if [[ -d "$DISABLED_DIR" ]]; then
        print_warning "Disabled directory already exists, appending timestamp"
        DISABLED_DIR="${CLUSTER_DIR}.disabled.$(date +%Y%m%d-%H%M%S)"
    fi
    mv "$CLUSTER_DIR" "$DISABLED_DIR"
    print_success "Cluster configuration moved to: $DISABLED_DIR"
else
    print_status "Removing cluster configuration..."
    rm -rf "$CLUSTER_DIR"
    print_success "Cluster configuration removed"
fi

# Step 3: Commit and push changes
print_status "Committing changes..."
safe_git_add "${ACCOUNT_DIR}"
if safe_git_commit "Destroy ${CLUSTER_NAME} cluster in ${ACCOUNT_NAME}"; then
    print_success "Changes committed"
    
    print_status "Pushing changes..."
    git push origin "$(get_current_branch)"
    print_success "Changes pushed"
else
    print_warning "No changes to commit"
fi

# Step 4: Wait for Flux to process the removal
if [[ "$FLUX_KUSTOMIZATION_EXISTS" == "true" ]]; then
    print_status "Waiting for Flux to remove the kustomization..."
    
    local start_time=$(date +%s)
    while kubectl get kustomization "$CLUSTER_NAME" -n flux-system &>/dev/null; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt 60 ]]; then
            print_warning "Flux kustomization still exists after 60 seconds"
            break
        fi
        
        echo -n "."
        sleep 5
    done
    echo
fi

# Step 5: Monitor cluster deletion if requested
if [[ "$WAIT" == "true" ]] && [[ "$CLUSTER_EXISTS" == "true" ]]; then
    print_status "Waiting for cluster deletion..."
    
    local start_time=$(date +%s)
    while true; do
        if ! kubectl get cluster "$CLUSTER_NAME" -n "$ACCOUNT_NAMESPACE" &>/dev/null; then
            print_success "Cluster has been deleted"
            break
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $TIMEOUT ]]; then
            print_error "Timeout waiting for cluster deletion after ${TIMEOUT}s"
            print_info "The cluster may still be deleting in the background"
            exit 1
        fi
        
        # Show cluster status
        local phase=$(kubectl get cluster "$CLUSTER_NAME" -n "$ACCOUNT_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo -ne "\rCluster phase: $phase (elapsed: ${elapsed}s)"
        
        sleep 10
    done
    echo
    
    # Check for remaining resources
    print_status "Checking for remaining resources..."
    local remaining_resources=$(kubectl get all -n "$ACCOUNT_NAMESPACE" -l "cluster.x-k8s.io/cluster-name=$CLUSTER_NAME" --no-headers 2>/dev/null | wc -l)
    if [[ $remaining_resources -gt 0 ]]; then
        print_warning "Found $remaining_resources resources still being cleaned up"
        kubectl get all -n "$ACCOUNT_NAMESPACE" -l "cluster.x-k8s.io/cluster-name=$CLUSTER_NAME"
    else
        print_success "All cluster resources have been removed"
    fi
fi

print_success "Cluster destruction initiated successfully!"

# Show next steps
echo
print_info "Next steps:"
echo "  - Monitor cluster deletion: kubectl get cluster -n $ACCOUNT_NAMESPACE"
echo "  - Check AWS resources: AWS Console > CloudFormation"
echo "  - View Flux events: flux events --for Kustomization/$ACCOUNT_NAME-account"

if [[ "$KEEP_CONFIG" == "true" ]]; then
    echo
    print_info "To restore this cluster later:"
    echo "  mv $DISABLED_DIR $CLUSTER_DIR"
    echo "  # Add cluster back to ${ACCOUNT_DIR}/kustomization.yaml"
    echo "  git add ${ACCOUNT_DIR} && git commit -m \"Restore $CLUSTER_NAME\""
fi