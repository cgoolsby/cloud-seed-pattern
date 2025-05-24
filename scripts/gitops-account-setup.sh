#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${GREEN}==> $1${NC}"
}

print_error() {
    echo -e "${RED}Error: $1${NC}"
}

print_info() {
    echo -e "${BLUE}Info: $1${NC}"
}

# Check if account alias is provided
if [ $# -eq 0 ]; then
    print_error "Please provide account alias as argument"
    echo "Usage: $0 <account-alias>"
    echo "Example: $0 demo-prod"
    echo ""
    echo "This script creates the GitOps configuration for a new AWS account."
    echo "Make sure you've already created the account in terraform/accounts first."
    exit 1
fi

ACCOUNT_ALIAS=$1
ACCOUNTS_DIR="kubernetes/accounts/overlays"
TEMPLATE_DIR="$ACCOUNTS_DIR/_template"
TARGET_DIR="$ACCOUNTS_DIR/$ACCOUNT_ALIAS"

# Check if we're in the root of the repo
if [ ! -f "scripts/gitops-account-setup.sh" ]; then
    print_error "Please run this script from the repository root"
    exit 1
fi

# Check if template exists
if [ ! -d "$TEMPLATE_DIR" ]; then
    print_error "Template directory not found at $TEMPLATE_DIR"
    exit 1
fi

# Check if account already exists
if [ -d "$TARGET_DIR" ]; then
    print_error "Account configuration already exists at $TARGET_DIR"
    exit 1
fi

# Get account info from ConfigMap if it exists
print_step "Checking for existing account information..."
ACCOUNT_ID=""
ACCOUNT_NAME=""
ENVIRONMENT=""

if kubectl get configmap -n crossplane-system aws-account-$ACCOUNT_ALIAS &>/dev/null; then
    print_info "Found account ConfigMap, extracting information..."
    ACCOUNT_ID=$(kubectl get configmap -n crossplane-system aws-account-$ACCOUNT_ALIAS -o jsonpath='{.data.ACCOUNT_ID}')
    ACCOUNT_NAME=$(kubectl get configmap -n crossplane-system aws-account-$ACCOUNT_ALIAS -o jsonpath='{.data.ACCOUNT_NAME}')
    ENVIRONMENT=$(kubectl get configmap -n crossplane-system aws-account-$ACCOUNT_ALIAS -o jsonpath='{.data.ENVIRONMENT}')
    print_info "Account ID: $ACCOUNT_ID"
    print_info "Account Name: $ACCOUNT_NAME"
    print_info "Environment: $ENVIRONMENT"
else
    print_info "Account ConfigMap not found. You'll need to update the values manually."
    print_info "Run 'terraform apply' in terraform/accounts first to create the account."
    
    # Prompt for values
    read -p "Enter Account ID: " ACCOUNT_ID
    read -p "Enter Account Name: " ACCOUNT_NAME
    read -p "Enter Environment (development/staging/production): " ENVIRONMENT
fi

# Determine CIDR based on environment
case $ENVIRONMENT in
    "production")
        CIDR="10.0.0.0/16"
        ;;
    "staging")
        CIDR="10.1.0.0/16"
        ;;
    "development")
        CIDR="10.2.0.0/16"
        ;;
    *)
        # Use a random block in 10.x.0.0/16
        RANDOM_OCTET=$((100 + RANDOM % 150))
        CIDR="10.$RANDOM_OCTET.0.0/16"
        print_info "Using CIDR: $CIDR"
        ;;
esac

# Copy template
print_step "Creating account configuration at $TARGET_DIR"
cp -r "$TEMPLATE_DIR" "$TARGET_DIR"

# Replace placeholders in all files
print_step "Updating configuration files..."
find "$TARGET_DIR" -type f -name "*.yaml" | while read -r file; do
    # Use temporary file for sed operations
    tmp_file="${file}.tmp"
    
    # Replace all placeholders
    sed -e "s/ACCOUNT-ALIAS/$ACCOUNT_ALIAS/g" \
        -e "s/ACCOUNT-ID/$ACCOUNT_ID/g" \
        -e "s/Account Name/$ACCOUNT_NAME/g" \
        -e "s/ENVIRONMENT/$ENVIRONMENT/g" \
        -e "s|10.X.0.0/16|$CIDR|g" \
        "$file" > "$tmp_file"
    
    mv "$tmp_file" "$file"
done

# Update the overlays kustomization.yaml to include the new account
print_step "Adding account to overlays kustomization..."
if ! grep -q "  - $ACCOUNT_ALIAS" "$ACCOUNTS_DIR/kustomization.yaml"; then
    # Add the new account before the comment line if it exists
    sed -i.bak "/# - demo-prod/i\\
  - $ACCOUNT_ALIAS" "$ACCOUNTS_DIR/kustomization.yaml" || \
    # If no comment exists, just append
    echo "  - $ACCOUNT_ALIAS" >> "$ACCOUNTS_DIR/kustomization.yaml"
    
    # Remove backup file
    rm -f "$ACCOUNTS_DIR/kustomization.yaml.bak"
fi

# Show summary
print_step "Account GitOps configuration created successfully!"
echo ""
echo "Files created in: $TARGET_DIR"
echo ""
echo "Next steps:"
echo "1. Review and adjust the configuration files if needed"
echo "2. Commit and push the changes:"
echo "   git add $TARGET_DIR"
echo "   git add $ACCOUNTS_DIR/kustomization.yaml"
echo "   git commit -m \"Add GitOps configuration for $ACCOUNT_ALIAS account\""
echo "   git push"
echo ""
echo "3. Flux will automatically create:"
echo "   - Namespace: aws-$ACCOUNT_ALIAS"
echo "   - Crossplane ProviderConfig"
echo "   - CAPA IAM roles"
echo "   - VPC with CIDR: $CIDR"
echo "   - CAPA cluster role identity"
echo ""
echo "4. Monitor the rollout:"
echo "   flux get kustomizations --watch"
echo "   kubectl get capaiamroles,vpc -n aws-$ACCOUNT_ALIAS"