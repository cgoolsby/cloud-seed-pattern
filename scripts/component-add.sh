#!/bin/bash
set -euo pipefail

# component-add.sh - Add a component to a cluster in a specific account

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source common functions
source "${SCRIPT_DIR}/common.sh"

# Help message
usage() {
    cat << EOF
Usage: $0 <component-name> <account-name> <cluster-name> [options]

Add a component to a specific cluster in an account.

Arguments:
    component-name    Name of the component to add (e.g., aws-ebs-csi, cert-manager)
    account-name      Name of the AWS account
    cluster-name      Name of the cluster

Options:
    -n, --namespace   Override the default namespace for the component
    -v, --values      Path to custom values file for the component
    -p, --priority    Set reconciliation priority (default: 100)
    -w, --wait        Wait for the component to be ready
    -t, --timeout     Timeout for waiting (default: 300s)
    -h, --help        Show this help message

Available Components:
EOF
    # List available components
    for comp in "${COMPONENTS_DIR}"/helmrelease/*.yaml; do
        if [[ -f "$comp" ]]; then
            basename "$comp" .yaml | sed 's/^/    - /'
        fi
    done
    
    cat << EOF

Examples:
    # Add cert-manager to a cluster
    $0 cert-manager dev-account primary-cluster

    # Add aws-ebs-csi with custom namespace
    $0 aws-ebs-csi prod-account prod-cluster -n kube-system

    # Add external-secrets and wait for it to be ready
    $0 external-secrets dev-account dev-cluster --wait

    # Add component with custom values
    $0 monitoring dev-account dev-cluster -v ./custom-monitoring-values.yaml
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
NAMESPACE=""
VALUES_FILE=""
PRIORITY="100"
WAIT="false"
TIMEOUT="300"

# Parse optional arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -v|--values)
            VALUES_FILE="$2"
            shift 2
            ;;
        -p|--priority)
            PRIORITY="$2"
            shift 2
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

if ! component_exists "$COMPONENT_NAME"; then
    print_error "Component not found: $COMPONENT_NAME"
    print_info "Available components:"
    for comp in "${COMPONENTS_DIR}"/helmrelease/*.yaml; do
        if [[ -f "$comp" ]]; then
            basename "$comp" .yaml | sed 's/^/    - /'
        fi
    done
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

if [[ -n "$VALUES_FILE" ]] && [[ ! -f "$VALUES_FILE" ]]; then
    print_error "Values file not found: $VALUES_FILE"
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

# Check if component is already added
if [[ -f "$COMPONENT_FILE" ]]; then
    print_warning "Component '$COMPONENT_NAME' is already added to cluster '$CLUSTER_NAME'"
    read -p "Do you want to update it? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled"
        exit 0
    fi
fi

print_status "Adding component '$COMPONENT_NAME' to cluster '$CLUSTER_NAME' in account '$ACCOUNT_NAME'"

# Create system directory if it doesn't exist
mkdir -p "$SYSTEM_DIR"

# Generate the component reference
cat > "$COMPONENT_FILE" << EOF
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ${CLUSTER_NAME}-${COMPONENT_NAME}
  namespace: flux-system
spec:
  interval: 10m
  path: ./components/helmrelease/${COMPONENT_NAME}
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  targetNamespace: ${NAMESPACE:-flux-system}
  dependsOn:
    - name: ${CLUSTER_NAME}
EOF

# Add priority if specified
if [[ "$PRIORITY" != "100" ]]; then
    cat >> "$COMPONENT_FILE" << EOF
  priority: ${PRIORITY}
EOF
fi

# Add postBuild if needed (for components that need variable substitution)
if grep -q "EBS_CSI_ROLE_ARN\|EFS_CSI_ROLE_ARN\|EXTERNAL_SECRETS_ROLE_ARN\|ALB_CONTROLLER_ROLE_ARN" "${COMPONENTS_DIR}/helmrelease/${COMPONENT_NAME}"/*.yaml 2>/dev/null || \
   grep -q "EBS_CSI_ROLE_ARN\|EFS_CSI_ROLE_ARN\|EXTERNAL_SECRETS_ROLE_ARN\|ALB_CONTROLLER_ROLE_ARN" "${COMPONENTS_DIR}/helmrelease/${COMPONENT_NAME}.yaml" 2>/dev/null; then
    cat >> "$COMPONENT_FILE" << EOF
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: terraform-outputs
        namespace: flux-system
EOF
fi

# Add custom values if provided
if [[ -n "$VALUES_FILE" ]]; then
    print_status "Adding custom values from $VALUES_FILE"
    VALUES_DIR="${SYSTEM_DIR}/values"
    mkdir -p "$VALUES_DIR"
    cp "$VALUES_FILE" "${VALUES_DIR}/${COMPONENT_NAME}-values.yaml"
    
    # Update the kustomization to include the values
    cat >> "$COMPONENT_FILE" << EOF
  valuesFiles:
    - ./system/values/${COMPONENT_NAME}-values.yaml
EOF
fi

# Update the system kustomization.yaml to include the new component
SYSTEM_KUSTOMIZATION="${SYSTEM_DIR}/kustomization.yaml"

if [[ ! -f "$SYSTEM_KUSTOMIZATION" ]]; then
    print_status "Creating system kustomization.yaml"
    cat > "$SYSTEM_KUSTOMIZATION" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ${COMPONENT_NAME}.yaml
EOF
else
    # Check if component is already in resources
    if ! grep -q "  - ${COMPONENT_NAME}.yaml" "$SYSTEM_KUSTOMIZATION"; then
        print_status "Adding component to system kustomization"
        # Use yq if available, otherwise use sed
        if command -v yq &>/dev/null; then
            yq eval -i '.resources += ["'${COMPONENT_NAME}'.yaml"]' "$SYSTEM_KUSTOMIZATION"
        else
            # Add to resources section (macOS compatible)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' -e '/^resources:/a\
  - '"${COMPONENT_NAME}.yaml" "$SYSTEM_KUSTOMIZATION"
            else
                sed -i '/^resources:/a\  - '"${COMPONENT_NAME}.yaml" "$SYSTEM_KUSTOMIZATION"
            fi
        fi
    fi
fi

# Commit the changes
print_status "Committing changes..."
safe_git_add "${CLUSTER_DIR}"
if safe_git_commit "Add ${COMPONENT_NAME} component to ${CLUSTER_NAME} cluster in ${ACCOUNT_NAME}"; then
    print_success "Changes committed"
else
    print_info "No changes to commit (component may already be configured)"
fi

# Push changes
print_status "Pushing changes..."
git push origin "$(get_current_branch)"

print_success "Component '${COMPONENT_NAME}' added to cluster '${CLUSTER_NAME}'"

# Wait for component if requested
if [[ "$WAIT" == "true" ]]; then
    print_status "Waiting for Flux to reconcile..."
    
    # First wait for the cluster kustomization
    wait_for_flux_kustomization "${CLUSTER_NAME}" "flux-system" "$TIMEOUT"
    
    # Then wait for the component kustomization
    wait_for_flux_kustomization "${CLUSTER_NAME}-${COMPONENT_NAME}" "flux-system" "$TIMEOUT"
    
    print_success "Component '${COMPONENT_NAME}' is ready"
fi

# Show status
print_info "To check component status:"
echo "  flux get kustomization ${CLUSTER_NAME}-${COMPONENT_NAME} -n flux-system"
echo "  kubectl get all -n ${NAMESPACE:-flux-system} -l app.kubernetes.io/name=${COMPONENT_NAME}"