#!/bin/bash

# Development workflow script for working with Flux-managed resources locally
# This script helps you pause Flux, work locally with kubectl, and manage git history

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
WORK_BRANCH_PREFIX="dev-work"
SESSION_FILE=".dev-session"
FLUX_KUSTOMIZATION="${FLUX_KUSTOMIZATION:-flux-system}"

# Helper functions
print_status() {
    echo -e "${BLUE}▶${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

Commands:
    start [description]    Start a new development session
    status                Show current session status
    checkpoint [message]  Create a checkpoint commit
    test <file/dir>       Apply resources locally for testing
    diff <file/dir>       Show what would change
    finish [message]      End session and create final commit
    abort                 Abort session and restore state

Options:
    -h, --help           Show this help message

Examples:
    $(basename "$0") start "debugging VPC composition"
    $(basename "$0") test kubernetes/infrastructure/aws/vpc/test-vpc.yaml
    $(basename "$0") checkpoint "fixed route table issue"
    $(basename "$0") finish "Fix VPC composition RouteTable associations"

EOF
}

# Check if we have an active session
has_active_session() {
    [ -f "$SESSION_FILE" ]
}

# Load session data
load_session() {
    if has_active_session; then
        source "$SESSION_FILE"
    fi
}

# Save session data
save_session() {
    cat > "$SESSION_FILE" << EOF
WORK_BRANCH="$WORK_BRANCH"
ORIGINAL_BRANCH="$ORIGINAL_BRANCH"
SESSION_START="$SESSION_START"
FLUX_WAS_SUSPENDED="$FLUX_WAS_SUSPENDED"
EOF
}

# Start a new development session
start_session() {
    if has_active_session; then
        print_error "A development session is already active!"
        print_status "Use 'status' to see current session or 'abort' to cancel it"
        exit 1
    fi

    local description="${1:-development work}"
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        print_error "You have uncommitted changes. Please commit or stash them first."
        exit 1
    fi

    print_status "Starting new development session: $description"
    
    # Store current branch
    ORIGINAL_BRANCH=$(git branch --show-current)
    
    # Create work branch
    WORK_BRANCH="${WORK_BRANCH_PREFIX}/$(date +%Y%m%d-%H%M%S)"
    git checkout -b "$WORK_BRANCH"
    print_success "Created work branch: $WORK_BRANCH"
    
    # Check Flux status and suspend if needed
    FLUX_WAS_SUSPENDED="false"
    if flux get kustomization "$FLUX_KUSTOMIZATION" -n flux-system | grep -q "True"; then
        print_status "Suspending Flux reconciliation..."
        flux suspend kustomization "$FLUX_KUSTOMIZATION"
        FLUX_WAS_SUSPENDED="true"
        print_success "Flux reconciliation suspended"
    else
        print_warning "Flux reconciliation was already suspended"
    fi
    
    # Save session info
    SESSION_START=$(date +%s)
    save_session
    
    print_success "Development session started!"
    echo
    print_status "Workflow:"
    echo "  1. Make changes to your Kubernetes manifests"
    echo "  2. Test with: $(basename "$0") test <file>"
    echo "  3. Create checkpoints: $(basename "$0") checkpoint \"what you did\""
    echo "  4. When done: $(basename "$0") finish \"final commit message\""
}

# Show session status
show_status() {
    if ! has_active_session; then
        print_status "No active development session"
        return
    fi
    
    load_session
    
    print_status "Active development session"
    echo "  Work branch: $WORK_BRANCH"
    echo "  Original branch: $ORIGINAL_BRANCH"
    echo "  Started: $(date -d @$SESSION_START 2>/dev/null || date -r $SESSION_START)"
    
    # Show checkpoint commits
    local commit_count=$(git rev-list --count "$ORIGINAL_BRANCH".."$WORK_BRANCH" 2>/dev/null || echo 0)
    echo "  Checkpoints: $commit_count"
    
    if [ "$commit_count" -gt 0 ]; then
        echo
        print_status "Recent checkpoints:"
        git log --oneline "$ORIGINAL_BRANCH".."$WORK_BRANCH" | head -5
    fi
    
    # Show Flux status
    echo
    print_status "Flux status:"
    flux get kustomization "$FLUX_KUSTOMIZATION" -n flux-system || true
}

# Create a checkpoint commit
create_checkpoint() {
    if ! has_active_session; then
        print_error "No active development session!"
        exit 1
    fi
    
    local message="${1:-WIP checkpoint}"
    
    # Add all changes
    git add -A
    
    # Check if there are changes to commit
    if git diff --cached --quiet; then
        print_warning "No changes to checkpoint"
        return
    fi
    
    # Create checkpoint commit
    git commit -m "checkpoint: $message"
    print_success "Created checkpoint: $message"
}

# Test resources locally
test_resources() {
    if ! has_active_session; then
        print_warning "No active session, but continuing anyway..."
    fi
    
    local resource="$1"
    
    if [ -z "$resource" ]; then
        print_error "Please specify a resource file or directory"
        exit 1
    fi
    
    print_status "Testing resource: $resource"
    
    # If it's a directory with kustomization.yaml, use kustomize
    if [ -d "$resource" ] && [ -f "$resource/kustomization.yaml" ]; then
        kubectl apply -k "$resource"
    else
        kubectl apply -f "$resource"
    fi
}

# Show diff for resources
diff_resources() {
    local resource="$1"
    
    if [ -z "$resource" ]; then
        print_error "Please specify a resource file or directory"
        exit 1
    fi
    
    print_status "Showing diff for: $resource"
    
    # If it's a directory with kustomization.yaml, use kustomize
    if [ -d "$resource" ] && [ -f "$resource/kustomization.yaml" ]; then
        kubectl diff -k "$resource" || true
    else
        kubectl diff -f "$resource" || true
    fi
}

# Finish development session
finish_session() {
    if ! has_active_session; then
        print_error "No active development session!"
        exit 1
    fi
    
    load_session
    
    local final_message="${1}"
    
    if [ -z "$final_message" ]; then
        print_error "Please provide a final commit message"
        echo "Usage: $(basename "$0") finish \"your commit message\""
        exit 1
    fi
    
    # Create final checkpoint if there are uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        create_checkpoint "final changes"
    fi
    
    # Count commits
    local commit_count=$(git rev-list --count "$ORIGINAL_BRANCH".."$WORK_BRANCH")
    
    if [ "$commit_count" -eq 0 ]; then
        print_warning "No commits to package"
    else
        print_status "Packaging $commit_count commits into final commit..."
        
        # Interactive rebase to squash commits
        print_status "Opening interactive rebase..."
        print_warning "Change all 'pick' to 'squash' except the first one"
        read -p "Press Enter to continue..."
        
        git rebase -i "$ORIGINAL_BRANCH"
        
        # Amend the commit message
        git commit --amend -m "$final_message"
        print_success "Created final commit"
    fi
    
    # Switch back to original branch
    git checkout "$ORIGINAL_BRANCH"
    
    # Merge the work
    if [ "$commit_count" -gt 0 ]; then
        print_status "Merging work into $ORIGINAL_BRANCH..."
        git merge --ff-only "$WORK_BRANCH"
        print_success "Work merged successfully"
    fi
    
    # Clean up work branch
    git branch -d "$WORK_BRANCH"
    
    # Resume Flux if we suspended it
    if [ "$FLUX_WAS_SUSPENDED" = "true" ]; then
        print_status "Resuming Flux reconciliation..."
        flux resume kustomization "$FLUX_KUSTOMIZATION"
        print_success "Flux reconciliation resumed"
    fi
    
    # Clean up session file
    rm -f "$SESSION_FILE"
    
    print_success "Development session finished!"
    echo
    print_status "Next steps:"
    echo "  - Review your changes: git show"
    echo "  - Push when ready: git push"
}

# Abort development session
abort_session() {
    if ! has_active_session; then
        print_error "No active development session!"
        exit 1
    fi
    
    load_session
    
    print_warning "Aborting development session..."
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        read -p "You have uncommitted changes. Discard them? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Abort cancelled"
            exit 1
        fi
        git reset --hard HEAD
    fi
    
    # Switch back to original branch
    git checkout "$ORIGINAL_BRANCH"
    
    # Delete work branch
    git branch -D "$WORK_BRANCH"
    
    # Resume Flux if we suspended it
    if [ "$FLUX_WAS_SUSPENDED" = "true" ]; then
        print_status "Resuming Flux reconciliation..."
        flux resume kustomization "$FLUX_KUSTOMIZATION"
        print_success "Flux reconciliation resumed"
    fi
    
    # Clean up session file
    rm -f "$SESSION_FILE"
    
    print_success "Development session aborted"
}

# Main command handler
case "${1:-help}" in
    start)
        start_session "$2"
        ;;
    status)
        show_status
        ;;
    checkpoint|cp)
        create_checkpoint "$2"
        ;;
    test)
        test_resources "$2"
        ;;
    diff)
        diff_resources "$2"
        ;;
    finish)
        finish_session "$2"
        ;;
    abort)
        abort_session
        ;;
    -h|--help|help)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac