# Crossplane Azure Provider Tests

This directory contains tests for validating the Crossplane Azure provider setup.

## Prerequisites

1. AKS cluster deployed with workload identity enabled (via Terraform)
2. Flux installed and reconciling
3. kubectl configured to access the cluster
4. Azure CLI (optional, for additional validation)

## Test Structure

### Unit Tests
- `test-resource-group.yaml` - Basic ResourceGroup creation test
- `test-storage-account.yaml` - Storage Account with dependency test

### Test Scripts
- `validate-azure-provider.sh` - Comprehensive validation script
- `Makefile` - Test automation targets

## Running Tests

### Quick Validation
```bash
# Run all tests
make test-all

# Run specific test suites
make test-provider   # Check provider installation
make test-auth      # Verify authentication setup
make test-resources # Test resource provisioning

# Clean up test resources
make clean
```

### Comprehensive Validation
```bash
# Run full validation script
./validate-azure-provider.sh
```

## What Gets Tested

1. **Provider Installation**
   - Provider package is installed
   - Provider pod is running
   - Provider reports healthy status

2. **Authentication**
   - Service account exists with correct annotations
   - Workload identity client ID is configured
   - ProviderConfig references correct credentials

3. **Resource Provisioning**
   - Can create Azure ResourceGroup
   - Can create dependent resources (Storage Account)
   - Resources reach Ready state

## Troubleshooting

If tests fail, check:

1. **Provider Logs**
   ```bash
   kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-azure
   ```

2. **Resource Status**
   ```bash
   kubectl describe resourcegroup.azure.upbound.io test-crossplane-azure-rg
   ```

3. **Authentication Issues**
   ```bash
   # Check federated credential subject
   kubectl get sa provider-azure -n crossplane-system -o yaml
   
   # Verify OIDC issuer
   kubectl get configmap terraform-outputs -n flux-system -o yaml
   ```

## CI/CD Integration

These tests can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions step
- name: Test Crossplane Azure Provider
  run: |
    cd tests/crossplane/azure
    make test-all
```