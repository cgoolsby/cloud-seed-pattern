# Create a Key Vault for storing secrets
resource "azurerm_key_vault" "main" {
  name                = "${substr(replace(var.cluster_name, "-", ""), 0, 20)}kv"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Enable RBAC authorization
  enable_rbac_authorization = true

  # Soft delete and purge protection
  soft_delete_retention_days = 7
  purge_protection_enabled   = false # Set to true in production

  tags = var.tags
}

# Managed Identity for External Secrets Operator
resource "azurerm_user_assigned_identity" "external_secrets" {
  name                = "${var.cluster_name}-external-secrets-identity"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  tags                = var.tags
}

# Federated credential for External Secrets service account
resource "azurerm_federated_identity_credential" "external_secrets" {
  name                = "external-secrets-federated"
  resource_group_name = azurerm_resource_group.aks.name
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.external_secrets.id
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject             = "system:serviceaccount:external-secrets:external-secrets"
}

# Role assignment for External Secrets to read from Key Vault
resource "azurerm_role_assignment" "external_secrets_key_vault_reader" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.external_secrets.principal_id
}

# Also grant the current user/service principal access to manage secrets
resource "azurerm_role_assignment" "current_user_key_vault_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}