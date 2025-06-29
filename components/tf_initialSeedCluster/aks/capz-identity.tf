# Managed Identity for Cluster API Provider Azure (CAPZ)
resource "azurerm_user_assigned_identity" "capz" {
  name                = "${var.cluster_name}-capz-identity"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  tags                = var.tags
}

# Federated credential for CAPZ controller manager
resource "azurerm_federated_identity_credential" "capz_controller" {
  name                = "capz-controller-federated"
  resource_group_name = azurerm_resource_group.aks.name
  audience            = ["api://AzureADTokenExchange"]
  parent_id           = azurerm_user_assigned_identity.capz.id
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject             = "system:serviceaccount:capz-system:capz-controller-manager"
}

# Role assignment for CAPZ to manage Azure resources
resource "azurerm_role_assignment" "capz_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.capz.principal_id
}

# Additional role for CAPZ to manage network resources
resource "azurerm_role_assignment" "capz_network_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.capz.principal_id
}

# Role assignment for CAPZ to manage role assignments (for managed identities)
resource "azurerm_role_assignment" "capz_user_access_admin" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "User Access Administrator"
  principal_id         = azurerm_user_assigned_identity.capz.principal_id
}