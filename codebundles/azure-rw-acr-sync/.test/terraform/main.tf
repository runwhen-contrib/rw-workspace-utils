# Cluster 1 Resources

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group
  location = "East US"
  tags     = var.tags
}

# Managed Identity
resource "azurerm_user_assigned_identity" "cluster_identity" {
  name                = "${var.cluster_name}-identity"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Role Assignment for Service Principal
resource "azurerm_role_assignment" "cluster_sp_owner" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.sp_principal_id
  principal_type       = "ServicePrincipal"
}
# Role Assignment for Service Principal
resource "azurerm_role_assignment" "cluster_sp_reader" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = var.sp_principal_id
  principal_type       = "ServicePrincipal"
}
# AKS Cluster
resource "azurerm_kubernetes_cluster" "cluster_aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = var.cluster_name

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_DC2s_v2"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster_identity.id]
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = var.tenant_id
  }

  tags = {
    "env"       = "test"
    "lifecycle" = "deleteme"
    "product"   = "runwhen"
  }
}

# Outputs for Cluster FQDNs
output "cluster_fqdn" {
  value = azurerm_kubernetes_cluster.cluster_aks.fqdn
}
output "cluster_name" {
  value = azurerm_kubernetes_cluster.cluster_aks.name
}
output "cluster_sub" {
  value = var.subscription_id
}
output "cluster_rg" {
  value = azurerm_kubernetes_cluster.cluster_aks.resource_group_name
}
