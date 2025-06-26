#!/bin/bash

# fpush.sh - Push staged files and trigger Flux reconciliation
# Usage: ./fpush.sh [git-repo-name] [kustomization-name]

set -e  # Exit on any error

# Configuration - modify these defaults as needed
DEFAULT_GIT_REPO="config-repo"
DEFAULT_KUSTOMIZATION="apps"
FLUX_NAMESPACE="flux-system"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not in a git repository"
        exit 1
    fi
}

# Function to check if there are staged files
check_staged_files() {
    if ! git diff --cached --quiet; then
        return 0  # There are staged files
    else
        print_warning "No staged files found"
        echo "Run 'git add <files>' to stage files before using fpush"
        exit 1
    fi
}

# Function to check if flux CLI is available
check_flux_cli() {
    if ! command -v flux &> /dev/null; then
        print_error "flux CLI not found. Please install flux CLI first."
        exit 1
    fi
}

# Function to get current branch
get_current_branch() {
    git branch --show-current
}

# Function to show staged files
show_staged_files() {
    print_status "Staged files:"
    git diff --cached --name-status | sed 's/^/  /'
}

# Function to commit with editor
commit_changes() {
    print_status "Opening commit message editor..."
    if ! git commit; then
        print_error "Commit cancelled or failed"
        exit 1
    fi
}

# Function to push changes
push_changes() {
    local branch=$(get_current_branch)
    print_status "Pushing to origin/$branch..."
    
    if git push origin "$branch"; then
        print_success "Successfully pushed to origin/$branch"
    else
        print_error "Failed to push changes"
        exit 1
    fi
}

# Function to reconcile flux
reconcile_flux() {
    local git_repo="${1:-$DEFAULT_GIT_REPO}"
    local kustomization="${2:-$DEFAULT_KUSTOMIZATION}"
    
    print_status "Triggering Flux reconciliation..."
    
    # Reconcile GitRepository first
    print_status "Reconciling GitRepository: $git_repo"
    if flux reconcile source git "$git_repo" -n "$FLUX_NAMESPACE"; then
        print_success "GitRepository reconciled successfully"
    else
        print_warning "GitRepository reconciliation failed or not found"
    fi
    
    # Wait a moment for GitRepository to update
    sleep 2
    
    # Reconcile Kustomization
    print_status "Reconciling Kustomization: $kustomization"
    if flux reconcile kustomization "$kustomization" -n "$FLUX_NAMESPACE"; then
        print_success "Kustomization reconciled successfully"
    else
        print_warning "Kustomization reconciliation failed or not found"
    fi
}

# Function to show help
show_help() {
    cat << EOF
fpush.sh - Git Push and Flux Reconcile Script

USAGE:
    ./fpush.sh [OPTIONS] [GIT_REPO_NAME] [KUSTOMIZATION_NAME]

DESCRIPTION:
    This script commits staged files with an interactive commit message,
    pushes to the current branch, and triggers Flux reconciliation.

ARGUMENTS:
    GIT_REPO_NAME        Name of the Flux GitRepository resource (default: $DEFAULT_GIT_REPO)
    KUSTOMIZATION_NAME   Name of the Flux Kustomization resource (default: $DEFAULT_KUSTOMIZATION)

OPTIONS:
    -h, --help          Show this help message
    -n, --namespace     Flux namespace (default: $FLUX_NAMESPACE)

EXAMPLES:
    ./fpush.sh                              # Use default names
    ./fpush.sh my-repo my-app              # Specify custom names
    ./fpush.sh -n custom-namespace my-repo # Use custom namespace

PREREQUISITES:
    - Must be run from within a git repository
    - Files must be staged with 'git add'
    - flux CLI must be installed and configured
    - Current context must be set to your development cluster

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--namespace)
            FLUX_NAMESPACE="$2"
            shift 2
            ;;
        -*)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            # Positional arguments
            if [[ -z "$GIT_REPO_ARG" ]]; then
                GIT_REPO_ARG="$1"
            elif [[ -z "$KUSTOMIZATION_ARG" ]]; then
                KUSTOMIZATION_ARG="$1"
            else
                print_error "Too many arguments"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Use provided arguments or defaults
GIT_REPO="${GIT_REPO_ARG:-$DEFAULT_GIT_REPO}"
KUSTOMIZATION="${KUSTOMIZATION_ARG:-$DEFAULT_KUSTOMIZATION}"

# Main execution
main() {
    print_status "Starting fpush workflow..."
    
    # Preflight checks
    check_git_repo
    check_staged_files
    check_flux_cli
    
    # Show current state
    local branch=$(get_current_branch)
    print_status "Current branch: $branch"
    show_staged_files
    
    # Git workflow
    commit_changes
    push_changes
    
    # Flux reconciliation
    reconcile_flux "$GIT_REPO" "$KUSTOMIZATION"
    
    print_success "fpush workflow completed successfully!"
    print_status "Your changes should be deploying to the cluster now."
    print_status "Use 'flux get kustomizations' to monitor deployment status."
}

# Run main function
main "$@"
