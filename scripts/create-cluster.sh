#!/bin/bash
set -euo pipefail

# create-cluster.sh - Create a new Kubernetes cluster using the template structure

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
print_success() { echo -e "${GREEN}SUCCESS: $1${NC}"; }
print_info() { echo -e "${YELLOW}INFO: $1${NC}"; }

# Function to substitute variables in templates
substitute_template() {
    local template_file=$1
    local output_file=$2
    
    # Use envsubst to replace variables
    envsubst < "${template_file}" > "${output_file}"
}

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
    -h, --help          Show this help message

Examples:
    # Create a dev cluster with defaults
    $0 test-account-1 dev-cluster

    # Create a production cluster with custom settings
    $0 prod-account prod-cluster -e production -n 3 -t t3.large

    # Create a cluster in a different region
    $0 test-account-1 regional-cluster -r us-west-2 -v 10.1.0.0/16
EOF
}

# Default values
REGION="us-east-1"
ENVIRONMENT="dev"
VPC_CIDR="10.0.0.0/16"
K8S_VERSION="1.28"
NODE_COUNT="2"
NODE_TYPE="t3.medium"

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

# Check if account directory exists
ACCOUNT_DIR="clusters/${ACCOUNT_NAME}"
if [[ ! -d "$ACCOUNT_DIR" ]]; then
    print_error "Account directory not found: $ACCOUNT_DIR"
    print_info "Please create the account structure first using the account setup script"
    exit 1
fi

# Check if cluster already exists
CLUSTER_DIR="${ACCOUNT_DIR}/${CLUSTER_NAME}"
if [[ -d "$CLUSTER_DIR" ]]; then
    print_error "Cluster directory already exists: $CLUSTER_DIR"
    exit 1
fi

# Calculate subnet CIDRs based on VPC CIDR
IFS='.' read -ra ADDR <<< "${VPC_CIDR%/*}"
SUBNET_PREFIX="${ADDR[0]}.${ADDR[1]}"

PUBLIC_SUBNET_A_CIDR="${SUBNET_PREFIX}.1.0/24"
PUBLIC_SUBNET_B_CIDR="${SUBNET_PREFIX}.2.0/24"
PRIVATE_SUBNET_A_CIDR="${SUBNET_PREFIX}.10.0/24"
PRIVATE_SUBNET_B_CIDR="${SUBNET_PREFIX}.11.0/24"

# Get account namespace and ID from account info
ACCOUNT_NAMESPACE="aws-${ACCOUNT_NAME}"

# Try to get account ID from existing ConfigMap
ACCOUNT_ID=$(kubectl get configmap account-info -n "${ACCOUNT_NAMESPACE}" -o jsonpath='{.data.ACCOUNT_ID}' 2>/dev/null || echo "")

if [[ -z "$ACCOUNT_ID" ]]; then
    print_error "Could not retrieve account ID from ConfigMap"
    print_info "Make sure the account namespace and ConfigMap exist"
    exit 1
fi

print_success "Input validation complete"

# Export all variables for envsubst
export CLUSTER_NAME ACCOUNT_NAME ACCOUNT_ID ACCOUNT_NAMESPACE
export REGION ENVIRONMENT VPC_CIDR
export PUBLIC_SUBNET_A_CIDR PUBLIC_SUBNET_B_CIDR
export PRIVATE_SUBNET_A_CIDR PRIVATE_SUBNET_B_CIDR
export K8S_VERSION NODE_COUNT NODE_TYPE

# Create cluster directory structure
print_info "Creating cluster directory structure..."
mkdir -p "${CLUSTER_DIR}"/{definition,networking,permissions,system}

# Create cluster configuration file
print_info "Creating cluster configuration..."
substitute_template "${TEMPLATE_DIR}/cluster-config.env.tmpl" "${CLUSTER_DIR}/cluster-config.env"

# Create main kustomization.yaml
print_info "Creating main kustomization file..."
substitute_template "${TEMPLATE_DIR}/cluster-kustomization.yaml.tmpl" "${CLUSTER_DIR}/kustomization.yaml"

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