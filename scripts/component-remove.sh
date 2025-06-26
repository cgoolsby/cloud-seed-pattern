#!/bin/bash
set -euo pipefail

# component-remove.sh - Remove a component from a cluster in a specific account

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source common functions
source "${SCRIPT_DIR}/common.sh"

# Help message
usage() {
    cat << EOF
Usage: $0 <component-name> <account-name> <cluster-name> [options]

Remove a component from a specific cluster in an account.

Arguments:
    component-name    Name of the component to remove (e.g., aws-ebs-csi, cert-manager)
    account-name      Name of the AWS account
    cluster-name      Name of the cluster

Options:
    -f, --force       Skip confirmation prompt
    -w, --wait        Wait for the component to be removed
    -t, --timeout     Timeout for waiting (default: 300s)
    -h, --help        Show this help message

Examples:
    # Remove cert-manager from a cluster
    $0 cert-manager dev-account primary-cluster

    # Remove aws-ebs-csi without confirmation
    $0 aws-ebs-csi prod-account prod-cluster --force

    # Remove external-secrets and wait for removal
    $0 external-secrets dev-account dev-cluster --wait

Notes:
    - This will remove the component reference from the cluster configuration
    - Flux will automatically clean up the component resources
    - Any custom values files will also be removed
EOF
    exit 1
}

# Parse arguments
if [[ $# -lt 3 ]]; then
    print_error "Missing required arguments"
    usage
fi

COMPONENT_NAME="$1"
ACCOUNT_NAME="$2"
CLUSTER_NAME="$3"
shift 3

# Optional parameters
FORCE="false"
WAIT="false"
TIMEOUT="300"

# Parse optional arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE="true"
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

if ! validate_component_name "$COMPONENT_NAME"; then
    exit 1
fi

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

# Set up paths
CLUSTER_DIR="${CLUSTERS_DIR}/${ACCOUNT_NAME}/${CLUSTER_NAME}"
SYSTEM_DIR="${CLUSTER_DIR}/system"
COMPONENT_FILE="${SYSTEM_DIR}/${COMPONENT_NAME}.yaml"
VALUES_FILE="${SYSTEM_DIR}/values/${COMPONENT_NAME}-values.yaml"

# Check if component exists in the cluster
if [[ ! -f "$COMPONENT_FILE" ]]; then
    print_error "Component '$COMPONENT_NAME' is not found in cluster '$CLUSTER_NAME'"
    exit 1
fi

# Confirm removal
if [[ "$FORCE" != "true" ]]; then
    print_warning "This will remove component '$COMPONENT_NAME' from cluster '$CLUSTER_NAME'"
    read -p "Are you sure you want to continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled"
        exit 0
    fi
fi

print_status "Removing component '$COMPONENT_NAME' from cluster '$CLUSTER_NAME' in account '$ACCOUNT_NAME'"

# Check if the component kustomization exists in the cluster
KUSTOMIZATION_NAME="${CLUSTER_NAME}-${COMPONENT_NAME}"
if kubectl get kustomization "$KUSTOMIZATION_NAME" -n flux-system &>/dev/null; then
    print_status "Component is currently deployed, it will be removed by Flux"
fi

# Remove the component file
print_status "Removing component configuration..."
rm -f "$COMPONENT_FILE"

# Remove custom values if they exist
if [[ -f "$VALUES_FILE" ]]; then
    print_status "Removing custom values file..."
    rm -f "$VALUES_FILE"
    
    # Remove values directory if empty
    if [[ -d "${SYSTEM_DIR}/values" ]] && [[ -z "$(ls -A "${SYSTEM_DIR}/values")" ]]; then
        rmdir "${SYSTEM_DIR}/values"
    fi
fi

# Update the system kustomization.yaml to remove the component
SYSTEM_KUSTOMIZATION="${SYSTEM_DIR}/kustomization.yaml"

if [[ -f "$SYSTEM_KUSTOMIZATION" ]]; then
    print_status "Updating system kustomization..."
    
    # Use yq if available, otherwise use sed
    if command -v yq &>/dev/null; then
        # Remove the component from resources array
        yq eval -i 'del(.resources[] | select(. == "'${COMPONENT_NAME}'.yaml"))' "$SYSTEM_KUSTOMIZATION"
    else
        # Remove the line containing the component (macOS compatible)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' -e "/  - ${COMPONENT_NAME}\.yaml/d" "$SYSTEM_KUSTOMIZATION"
        else
            sed -i "/  - ${COMPONENT_NAME}\.yaml/d" "$SYSTEM_KUSTOMIZATION"
        fi
    fi
    
    # Check if resources section is empty
    if grep -q "^resources:\s*$" "$SYSTEM_KUSTOMIZATION" && ! grep -q "^  - " "$SYSTEM_KUSTOMIZATION"; then
        print_warning "System kustomization has no more resources"
        # Optionally remove the empty kustomization file
        # rm -f "$SYSTEM_KUSTOMIZATION"
    fi
fi

# Commit the changes
print_status "Committing changes..."
safe_git_add "${CLUSTER_DIR}"
if safe_git_commit "Remove ${COMPONENT_NAME} component from ${CLUSTER_NAME} cluster in ${ACCOUNT_NAME}"; then
    print_success "Changes committed"
else
    print_error "Failed to commit changes"
    exit 1
fi

# Push changes
print_status "Pushing changes..."
git push origin "$(get_current_branch)"

print_success "Component '${COMPONENT_NAME}' removed from cluster '${CLUSTER_NAME}' configuration"

# Wait for component removal if requested
if [[ "$WAIT" == "true" ]]; then
    print_status "Waiting for component to be removed..."
    
    local start_time=$(date +%s)
    while true; do
        if ! kubectl get kustomization "$KUSTOMIZATION_NAME" -n flux-system &>/dev/null; then
            print_success "Component kustomization has been removed"
            break
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $TIMEOUT ]]; then
            print_warning "Timeout waiting for component removal"
            print_info "The component may still be in the process of being removed"
            break
        fi
        
        echo -n "."
        sleep 5
    done
    
    # Check if any resources still exist
    print_status "Checking for remaining resources..."
    local remaining=$(kubectl get all -A -l "app.kubernetes.io/name=${COMPONENT_NAME}" --no-headers 2>/dev/null | wc -l)
    if [[ $remaining -gt 0 ]]; then
        print_warning "Found $remaining resources still present. They may take time to be fully removed."
    else
        print_success "All component resources have been removed"
    fi
fi

# Show status
print_info "Component removal initiated. Flux will clean up the resources."
echo "To check removal progress:"
echo "  flux get kustomization ${CLUSTER_NAME} -n flux-system"
echo "  kubectl get all -A -l app.kubernetes.io/name=${COMPONENT_NAME}"