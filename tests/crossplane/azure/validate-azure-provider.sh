#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Validating Crossplane Azure Provider Setup..."

# Function to check if a resource exists and is ready
check_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-crossplane-system}
    local field=${4:-status.conditions[?(@.type=='Ready')].status}
    
    echo -n "Checking $resource_type/$resource_name... "
    
    if kubectl get "$resource_type" "$resource_name" -n "$namespace" &>/dev/null; then
        local status=$(kubectl get "$resource_type" "$resource_name" -n "$namespace" -o jsonpath="{.$field}" 2>/dev/null || echo "Unknown")
        if [[ "$status" == "True" ]]; then
            echo -e "${GREEN}✓${NC} Ready"
            return 0
        else
            echo -e "${YELLOW}⚠${NC} Not ready (status: $status)"
            kubectl describe "$resource_type" "$resource_name" -n "$namespace" | grep -A 10 "Conditions:" || true
            return 1
        fi
    else
        echo -e "${RED}✗${NC} Not found"
        return 1
    fi
}

# Check if cluster has workload identity enabled
echo -e "\n📋 Checking AKS Workload Identity Configuration..."
if command -v az &>/dev/null; then
    CLUSTER_NAME="${CLUSTER_NAME:-fullStack-cluster}"
    RESOURCE_GROUP=$(kubectl get configmap terraform-outputs -n flux-system -o jsonpath='{.data.RESOURCE_GROUP}' 2>/dev/null || echo "")
    
    if [[ -n "$RESOURCE_GROUP" ]]; then
        echo -n "Checking AKS OIDC issuer... "
        OIDC_ISSUER=$(az aks show -n "$CLUSTER_NAME" -g "$RESOURCE_GROUP" --query "oidcIssuerProfile.issuerUrl" -o tsv 2>/dev/null || echo "")
        if [[ -n "$OIDC_ISSUER" ]]; then
            echo -e "${GREEN}✓${NC} Enabled"
            echo "  OIDC Issuer: $OIDC_ISSUER"
        else
            echo -e "${RED}✗${NC} Not enabled"
        fi
    fi
else
    echo "⚠️  Azure CLI not installed, skipping AKS checks"
fi

# Check Terraform outputs ConfigMap
echo -e "\n📋 Checking Terraform Outputs..."
if kubectl get configmap terraform-outputs -n flux-system &>/dev/null; then
    echo -e "${GREEN}✓${NC} ConfigMap 'terraform-outputs' exists"
    
    # Check for required Azure keys
    for key in AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID CROSSPLANE_CLIENT_ID; do
        value=$(kubectl get configmap terraform-outputs -n flux-system -o jsonpath="{.data.$key}" 2>/dev/null || echo "")
        if [[ -n "$value" ]]; then
            echo -e "  ${GREEN}✓${NC} $key is set"
        else
            echo -e "  ${RED}✗${NC} $key is missing"
        fi
    done
else
    echo -e "${RED}✗${NC} ConfigMap 'terraform-outputs' not found in flux-system namespace"
    echo "  Have you applied the Terraform configuration?"
fi

# Check ServiceAccount
echo -e "\n📋 Checking Service Account..."
check_resource serviceaccount provider-azure crossplane-system

# Verify workload identity annotations
if kubectl get serviceaccount provider-azure -n crossplane-system &>/dev/null; then
    CLIENT_ID=$(kubectl get serviceaccount provider-azure -n crossplane-system -o jsonpath='{.metadata.annotations.azure\.workload\.identity/client-id}' 2>/dev/null || echo "")
    if [[ -n "$CLIENT_ID" ]]; then
        echo -e "  ${GREEN}✓${NC} Workload identity client ID: $CLIENT_ID"
    else
        echo -e "  ${RED}✗${NC} Missing workload identity annotations"
    fi
fi

# Check Provider
echo -e "\n📋 Checking Crossplane Provider..."
check_resource provider.pkg.crossplane.io provider-azure "" "status.conditions[?(@.type=='Healthy')].status"

# Check if provider pod is running
echo -e "\n📋 Checking Provider Pod..."
PROVIDER_POD=$(kubectl get pods -n crossplane-system -l pkg.crossplane.io/provider=provider-azure -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$PROVIDER_POD" ]]; then
    check_resource pod "$PROVIDER_POD" crossplane-system "status.phase"
    
    # Check for workload identity environment variables
    echo -n "Checking workload identity setup in pod... "
    AZURE_AUTHORITY_HOST=$(kubectl exec -n crossplane-system "$PROVIDER_POD" -- printenv AZURE_AUTHORITY_HOST 2>/dev/null || echo "")
    if [[ -n "$AZURE_AUTHORITY_HOST" ]]; then
        echo -e "${GREEN}✓${NC} Workload identity environment configured"
    else
        echo -e "${YELLOW}⚠${NC} Workload identity environment may not be configured"
    fi
else
    echo -e "${RED}✗${NC} No provider pod found"
fi

# Check ProviderConfig
echo -e "\n📋 Checking Provider Configuration..."
check_resource providerconfig.azure.upbound.io default

# Test creating a resource
echo -e "\n🧪 Testing Resource Creation..."
echo "Creating test ResourceGroup..."

# Apply test resource
kubectl apply -f test-resource-group.yaml

# Wait for resource to be ready (max 60 seconds)
echo -n "Waiting for ResourceGroup to be ready... "
for i in {1..60}; do
    if kubectl get resourcegroup.azure.upbound.io test-crossplane-azure-rg -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        echo -e "${GREEN}✓${NC} Ready"
        break
    elif [[ $i -eq 60 ]]; then
        echo -e "${RED}✗${NC} Timeout"
        echo "Resource status:"
        kubectl describe resourcegroup.azure.upbound.io test-crossplane-azure-rg | grep -A 20 "Status:"
    else
        echo -n "."
        sleep 1
    fi
done

# Cleanup
echo -e "\n🧹 Cleaning up test resources..."
kubectl delete -f test-resource-group.yaml --wait=false 2>/dev/null || true

echo -e "\n✅ Validation complete!"