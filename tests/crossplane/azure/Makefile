.PHONY: help test-all test-provider test-auth test-resources clean

# Default target
help:
	@echo "Crossplane Azure Provider Tests"
	@echo "=============================="
	@echo "make test-all        - Run all tests"
	@echo "make test-provider   - Test provider installation"
	@echo "make test-auth       - Test authentication setup"
	@echo "make test-resources  - Test resource provisioning"
	@echo "make clean          - Clean up test resources"

# Run all tests
test-all: test-provider test-auth test-resources
	@echo "✅ All tests completed"

# Test provider installation
test-provider:
	@echo "🔍 Testing Provider Installation..."
	@kubectl get provider.pkg.crossplane.io provider-azure || (echo "❌ Provider not installed" && exit 1)
	@kubectl wait --for=condition=Healthy provider.pkg.crossplane.io/provider-azure --timeout=300s || (echo "❌ Provider not healthy" && exit 1)
	@echo "✅ Provider installed and healthy"

# Test authentication setup
test-auth:
	@echo "🔍 Testing Authentication Setup..."
	@# Check service account
	@kubectl get sa provider-azure -n crossplane-system || (echo "❌ Service account not found" && exit 1)
	@# Check workload identity annotation
	@kubectl get sa provider-azure -n crossplane-system -o jsonpath='{.metadata.annotations.azure\.workload\.identity/client-id}' | grep -q . || (echo "❌ Workload identity not configured" && exit 1)
	@# Check provider config
	@kubectl get providerconfig.azure.upbound.io default || (echo "❌ ProviderConfig not found" && exit 1)
	@echo "✅ Authentication configured"

# Test resource provisioning
test-resources:
	@echo "🔍 Testing Resource Provisioning..."
	@# Apply test resource
	@kubectl apply -f test-resource-group.yaml
	@# Wait for ready condition
	@kubectl wait --for=condition=Ready resourcegroup.azure.upbound.io/test-crossplane-azure-rg --timeout=120s || (echo "❌ Resource provisioning failed" && kubectl describe resourcegroup.azure.upbound.io/test-crossplane-azure-rg && exit 1)
	@echo "✅ Resource provisioning successful"
	@# Test storage account
	@kubectl apply -f test-storage-account.yaml
	@kubectl wait --for=condition=Ready account.storage.azure.upbound.io/testcrossplaneazure001 --timeout=180s || (echo "❌ Storage account provisioning failed" && exit 1)
	@echo "✅ Storage account provisioning successful"

# Clean up test resources
clean:
	@echo "🧹 Cleaning up test resources..."
	@kubectl delete -f test-storage-account.yaml --ignore-not-found=true
	@kubectl delete -f test-resource-group.yaml --ignore-not-found=true
	@echo "✅ Cleanup complete"

# Run validation script
validate:
	@./validate-azure-provider.sh