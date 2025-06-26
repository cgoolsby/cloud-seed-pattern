#!/bin/bash
# common.sh - Shared functions and utilities for cloud-seed-pattern scripts

# Color codes for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export MAGENTA='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# Default repository configuration
export DEFAULT_GITHUB_OWNER="cgoolsby"
export DEFAULT_REPO_NAME="cloud-seed-pattern"
export DEFAULT_BRANCH="main"
export DEFAULT_REGION="us-east-1"
export DEFAULT_ENVIRONMENT="dev"
export DEFAULT_VPC_CIDR="10.0.0.0/16"
export DEFAULT_K8S_VERSION="1.28"
export DEFAULT_NODE_COUNT="2"
export DEFAULT_NODE_TYPE="t3.medium"

# Paths
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPTS_DIR="${REPO_ROOT}/scripts"
export TEMPLATES_DIR="${SCRIPTS_DIR}/templates"
export CLUSTERS_DIR="${REPO_ROOT}/clusters"
export COMPONENTS_DIR="${REPO_ROOT}/components"

# Common output functions
print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

print_status() {
    echo -e "${BLUE}▶ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${CYAN}DEBUG: $1${NC}" >&2
    fi
}

# Validation functions
validate_account_name() {
    local account_name=$1
    if [[ ! "$account_name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        print_error "Invalid account name: $account_name"
        print_info "Account name must start with a letter and contain only lowercase letters, numbers, and hyphens"
        return 1
    fi
    return 0
}

validate_cluster_name() {
    local cluster_name=$1
    if [[ ! "$cluster_name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        print_error "Invalid cluster name: $cluster_name"
        print_info "Cluster name must start with a letter and contain only lowercase letters, numbers, and hyphens"
        return 1
    fi
    return 0
}

validate_component_name() {
    local component_name=$1
    if [[ ! "$component_name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        print_error "Invalid component name: $component_name"
        print_info "Component name must start with a letter and contain only lowercase letters, numbers, and hyphens"
        return 1
    fi
    return 0
}

# Check if account exists
account_exists() {
    local account_name=$1
    [[ -d "${CLUSTERS_DIR}/${account_name}" ]]
}

# Check if cluster exists
cluster_exists() {
    local account_name=$1
    local cluster_name=$2
    [[ -d "${CLUSTERS_DIR}/${account_name}/${cluster_name}" ]]
}

# Check if component exists
component_exists() {
    local component_name=$1
    [[ -f "${COMPONENTS_DIR}/helmrelease/${component_name}.yaml" ]] || \
    [[ -d "${COMPONENTS_DIR}/helmrelease/${component_name}" ]]
}

# Get account namespace
get_account_namespace() {
    local account_name=$1
    echo "aws-${account_name}"
}

# Get account ID from ConfigMap
get_account_id() {
    local account_name=$1
    local namespace=$(get_account_namespace "$account_name")
    
    kubectl get configmap account-info -n "${namespace}" -o jsonpath='{.data.ACCOUNT_ID}' 2>/dev/null || echo ""
}

# Check if kubectl is configured
check_kubectl() {
    if ! kubectl cluster-info &>/dev/null; then
        print_error "kubectl is not configured or cluster is not accessible"
        return 1
    fi
    return 0
}

# Check if flux is installed
check_flux() {
    if ! command -v flux &>/dev/null; then
        print_error "Flux CLI is not installed"
        print_info "Install with: brew install fluxcd/tap/flux"
        return 1
    fi
    return 0
}

# Check if required tools are installed
check_required_tools() {
    local tools=("kubectl" "git" "flux")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi
    
    return 0
}

# Template substitution function
substitute_template() {
    local template_file=$1
    local output_file=$2
    
    if [[ ! -f "$template_file" ]]; then
        print_error "Template file not found: $template_file"
        return 1
    fi
    
    # Create output directory if it doesn't exist
    local output_dir=$(dirname "$output_file")
    mkdir -p "$output_dir"
    
    # Use envsubst to replace variables
    envsubst < "${template_file}" > "${output_file}"
}

# Calculate subnet CIDRs based on VPC CIDR
calculate_subnets() {
    local vpc_cidr=$1
    
    # Extract base octets
    IFS='.' read -ra ADDR <<< "${vpc_cidr%/*}"
    local subnet_prefix="${ADDR[0]}.${ADDR[1]}"
    
    # Export subnet variables
    export PUBLIC_SUBNET_A_CIDR="${subnet_prefix}.1.0/24"
    export PUBLIC_SUBNET_B_CIDR="${subnet_prefix}.2.0/24"
    export PRIVATE_SUBNET_A_CIDR="${subnet_prefix}.10.0/24"
    export PRIVATE_SUBNET_B_CIDR="${subnet_prefix}.11.0/24"
}

# Wait for Flux kustomization to be ready
wait_for_flux_kustomization() {
    local name=$1
    local namespace=${2:-flux-system}
    local timeout=${3:-300}
    
    print_status "Waiting for Flux kustomization '$name' to be ready..."
    
    local start_time=$(date +%s)
    while true; do
        local status=$(kubectl get kustomization "$name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        
        if [[ "$status" == "True" ]]; then
            print_success "Kustomization '$name' is ready"
            return 0
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            print_error "Timeout waiting for kustomization '$name' to be ready"
            return 1
        fi
        
        echo -n "."
        sleep 5
    done
}

# Git operations with error handling
safe_git_add() {
    local path=$1
    if [[ -e "$path" ]]; then
        git add "$path"
    else
        print_warning "Path not found for git add: $path"
    fi
}

safe_git_commit() {
    local message=$1
    if ! git diff --cached --quiet; then
        git commit -m "$message"
        return 0
    else
        print_debug "No changes to commit"
        return 1
    fi
}

# Check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir &>/dev/null; then
        print_error "Not in a git repository"
        return 1
    fi
    return 0
}

# Get current git branch
get_current_branch() {
    git branch --show-current 2>/dev/null || echo "main"
}

# Export common functions for use in other scripts
export -f print_error print_success print_info print_status print_warning print_debug
export -f validate_account_name validate_cluster_name validate_component_name
export -f account_exists cluster_exists component_exists
export -f get_account_namespace get_account_id
export -f check_kubectl check_flux check_required_tools
export -f substitute_template calculate_subnets
export -f wait_for_flux_kustomization
export -f safe_git_add safe_git_commit check_git_repo get_current_branch