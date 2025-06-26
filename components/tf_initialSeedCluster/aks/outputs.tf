output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.id
}

output "kube_config" {
  description = "Kubernetes config for connecting to the cluster"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

output "kube_config_host" {
  description = "Kubernetes API server endpoint"
  value       = azurerm_kubernetes_cluster.aks.kube_config.0.host
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.aks.name
}

output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.aks.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.aks.name
}

output "aks_subnet_id" {
  description = "ID of the AKS subnet"
  value       = azurerm_subnet.aks.id
}

output "cluster_identity_principal_id" {
  description = "Principal ID of the cluster managed identity"
  value       = azurerm_kubernetes_cluster.aks.identity.0.principal_id
}

output "node_resource_group" {
  description = "Name of the auto-generated resource group for AKS nodes"
  value       = azurerm_kubernetes_cluster.aks.node_resource_group
}