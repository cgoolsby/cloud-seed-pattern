# Data source for current Azure configuration
data "azurerm_client_config" "current" {}

# Managed Identity for Crossplane Provider Azure
resource "azurerm_user_assigned_identity" "crossplane" {
  name                = "${var.cluster_name}-crossplane-identity"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  tags                = var.tags
}

# Federated credential for Crossplane service accounts
# Using wildcard pattern to match dynamic service account names
resource "azurerm_federated_identity_credential" "crossplane" {
  name                = "crossplane-federated"
  resource_group_name = azurerm_resource_group.aks.name
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.crossplane.id
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject             = "system:serviceaccount:crossplane-system:provider-azure-*"
}

# Role assignment for Crossplane to manage resources in current subscription
resource "azurerm_role_assignment" "crossplane_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.crossplane.principal_id
}

# Additional role for managing role assignments (needed for cross-subscription access)
resource "azurerm_role_assignment" "crossplane_user_access_admin" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "User Access Administrator"
  principal_id         = azurerm_user_assigned_identity.crossplane.principal_id
}