#!/bin/bash
set -euo pipefail

# create-cluster.sh - Create a new Kubernetes cluster using the template structure

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source common functions
source "${SCRIPT_DIR}/common.sh"

# Function to show usage
usage() {
    cat << EOF
Usage: $0 <account-name> <cluster-name> [options]

Create a new Kubernetes cluster in the specified account.

Arguments:
    account-name    Name of the AWS account (e.g., test-account-1)
    cluster-name    Name of the cluster to create

Options:
    -r, --region        AWS region (default: us-east-1)
    -e, --environment   Environment tag (default: dev)
    -v, --vpc-cidr      VPC CIDR block (default: 10.0.0.0/16)
    -k, --k8s-version   Kubernetes version (default: 1.28)
    -n, --node-count    Number of worker nodes (default: 2)
    -t, --node-type     EC2 instance type for nodes (default: t3.medium)
    -m, --management    Create as a management cluster with Crossplane and Cluster API
    -h, --help          Show this help message

Examples:
    # Create a dev cluster with defaults
    $0 test-account-1 dev-cluster

    # Create a production cluster with custom settings
    $0 prod-account prod-cluster -e production -n 3 -t t3.large

    # Create a cluster in a different region
    $0 test-account-1 regional-cluster -r us-west-2 -v 10.1.0.0/16

    # Create a management cluster with Crossplane and Cluster API
    $0 test-account-1 mgmt-cluster --management
EOF
}

# Script-specific defaults
REGION="${DEFAULT_REGION}"
ENVIRONMENT="${DEFAULT_ENVIRONMENT}"
VPC_CIDR="${DEFAULT_VPC_CIDR}"
K8S_VERSION="${DEFAULT_K8S_VERSION}"
NODE_COUNT="${DEFAULT_NODE_COUNT}"
NODE_TYPE="${DEFAULT_NODE_TYPE}"
MANAGEMENT="false"

# Parse command line arguments
if [[ $# -lt 2 ]]; then
    print_error "Missing required arguments"
    usage
    exit 1
fi

ACCOUNT_NAME="$1"
CLUSTER_NAME="$2"
shift 2

# Parse optional arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -v|--vpc-cidr)
            VPC_CIDR="$2"
            shift 2
            ;;
        -k|--k8s-version)
            K8S_VERSION="$2"
            shift 2
            ;;
        -n|--node-count)
            NODE_COUNT="$2"
            shift 2
            ;;
        -t|--node-type)
            NODE_TYPE="$2"
            shift 2
            ;;
        -m|--management)
            MANAGEMENT="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
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
    print_error "Account directory not found: clusters/${ACCOUNT_NAME}"
    print_info "Please create the account structure first using the account setup script"
    exit 1
fi

if cluster_exists "$ACCOUNT_NAME" "$CLUSTER_NAME"; then
    print_error "Cluster already exists: ${ACCOUNT_NAME}/${CLUSTER_NAME}"
    exit 1
fi

# Check required tools
if ! check_required_tools; then
    exit 1
fi

if ! check_kubectl; then
    exit 1
fi

# Calculate subnet CIDRs
calculate_subnets "$VPC_CIDR"

# Get account namespace and ID
ACCOUNT_NAMESPACE=$(get_account_namespace "$ACCOUNT_NAME")
ACCOUNT_ID=$(get_account_id "$ACCOUNT_NAME")

if [[ -z "$ACCOUNT_ID" ]]; then
    print_error "Could not retrieve account ID from ConfigMap"
    print_info "Make sure the account namespace and ConfigMap exist"
    exit 1
fi

# Set up paths
CLUSTER_DIR="${CLUSTERS_DIR}/${ACCOUNT_NAME}/${CLUSTER_NAME}"

print_success "Input validation complete"

# Export all variables for envsubst
export CLUSTER_NAME ACCOUNT_NAME ACCOUNT_ID ACCOUNT_NAMESPACE
export REGION ENVIRONMENT VPC_CIDR
export PUBLIC_SUBNET_A_CIDR PUBLIC_SUBNET_B_CIDR
export PRIVATE_SUBNET_A_CIDR PRIVATE_SUBNET_B_CIDR
export K8S_VERSION NODE_COUNT NODE_TYPE

# Create cluster directory structure
print_info "Creating cluster directory structure..."
if [[ "$MANAGEMENT" == "true" ]]; then
    mkdir -p "${CLUSTER_DIR}"/{definition,networking,permissions,system,management}
else
    mkdir -p "${CLUSTER_DIR}"/{definition,networking,permissions,system}
fi

# Create cluster configuration file
print_info "Creating cluster configuration..."
substitute_template "${TEMPLATE_DIR}/cluster-config.env.tmpl" "${CLUSTER_DIR}/cluster-config.env"

# Create main kustomization.yaml
print_info "Creating main kustomization file..."
if [[ "$MANAGEMENT" == "true" ]]; then
    substitute_template "${TEMPLATE_DIR}/cluster-kustomization-mgmt.yaml.tmpl" "${CLUSTER_DIR}/kustomization.yaml"
else
    substitute_template "${TEMPLATE_DIR}/cluster-kustomization.yaml.tmpl" "${CLUSTER_DIR}/kustomization.yaml"
fi

# Create networking resources
print_info "Setting up networking configuration..."
cp -r clusters/_template/networking/* "${CLUSTER_DIR}/networking/"

# Create permissions resources
print_info "Setting up permissions configuration..."
cp -r clusters/_template/permissions/* "${CLUSTER_DIR}/permissions/"

# Create placeholder for cluster definition
print_info "Creating cluster definition placeholder..."
substitute_template "${TEMPLATE_DIR}/definition-kustomization.yaml.tmpl" "${CLUSTER_DIR}/definition/kustomization.yaml"

# Create placeholder for system components
print_info "Creating system components placeholder..."
cp -r clusters/_template/system/* "${CLUSTER_DIR}/system/" 2>/dev/null || {
    substitute_template "${TEMPLATE_DIR}/system-kustomization.yaml.tmpl" "${CLUSTER_DIR}/system/kustomization.yaml"
}

# Create management components if requested
if [[ "$MANAGEMENT" == "true" ]]; then
    print_info "Creating management components..."
    substitute_template "${TEMPLATE_DIR}/management-kustomization.yaml.tmpl" "${CLUSTER_DIR}/management/kustomization.yaml"
    substitute_template "${TEMPLATE_DIR}/management-crossplane.yaml.tmpl" "${CLUSTER_DIR}/management/crossplane.yaml"
    substitute_template "${TEMPLATE_DIR}/management-cluster-api.yaml.tmpl" "${CLUSTER_DIR}/management/cluster-api.yaml"
fi

# Create Flux Kustomization for the cluster
print_info "Creating Flux Kustomization..."
substitute_template "${TEMPLATE_DIR}/flux-kustomization.yaml.tmpl" "${CLUSTER_DIR}/flux-kustomization.yaml"

# Add cluster to account kustomization
print_info "Adding cluster to account kustomization..."
if grep -q "${CLUSTER_NAME}" "${ACCOUNT_DIR}/kustomization.yaml"; then
    print_info "Cluster already referenced in account kustomization"
else
    # Add the cluster directory to resources (macOS compatible)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' -e '/^resources:/a\
  - '"${CLUSTER_NAME}" "${ACCOUNT_DIR}/kustomization.yaml"
    else
        sed -i '/^resources:/a\  - '"${CLUSTER_NAME}" "${ACCOUNT_DIR}/kustomization.yaml"
    fi
fi

# Summary
print_success "Cluster structure created successfully!"
echo ""
echo "Cluster Details:"
echo "  Name: ${CLUSTER_NAME}"
echo "  Account: ${ACCOUNT_NAME}"
echo "  Namespace: ${ACCOUNT_NAMESPACE}"
echo "  Region: ${REGION}"
echo "  VPC CIDR: ${VPC_CIDR}"
if [[ "$MANAGEMENT" == "true" ]]; then
    echo "  Type: Management Cluster (with Crossplane & Cluster API)"
fi
echo ""
echo "Next steps:"
echo "1. Review and customize the configuration in ${CLUSTER_DIR}/"
echo "2. Add cluster definition resources to ${CLUSTER_DIR}/definition/"
echo "3. Commit and push the changes"
echo "4. Flux will automatically create the cluster resources"
echo ""
echo "To monitor the deployment:"
echo "  flux get kustomization ${CLUSTER_NAME} -n flux-system"
echo "  kubectl get cluster -n ${ACCOUNT_NAMESPACE} ${CLUSTER_NAME}"