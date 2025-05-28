terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# Import provider configs from EKS module
data "terraform_remote_state" "eks" {
  backend = "local"
  config = {
    path = "../eks/terraform.tfstate"
  }
}

provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name]
  }
}

# Enable AWS Organizations (only needed once)
resource "aws_organizations_organization" "org" {
  count = var.create_organization ? 1 : 0
  
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "sso.amazonaws.com"
  ]

  feature_set = "ALL"
}

# Create AWS accounts
resource "aws_organizations_account" "accounts" {
  for_each = var.accounts

  name              = each.value.name
  email             = each.value.email
  iam_user_access_to_billing = "ALLOW"
  
  # Automatically create account alias
  lifecycle {
    ignore_changes = [email]
  }
}


# Create ConfigMap for each account
resource "kubernetes_config_map" "account_configs" {
  for_each = aws_organizations_account.accounts

  metadata {
    name      = "aws-account-${each.key}"
    namespace = "crossplane-system"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "multi-account-setup"
      "account.aws/environment"       = var.accounts[each.key].environment
    }
  }

  data = {
    ACCOUNT_ID        = each.value.id
    ACCOUNT_NAME      = each.value.name
    ACCOUNT_ALIAS     = each.key
    ACCOUNT_EMAIL     = each.value.email
    ENVIRONMENT       = var.accounts[each.key].environment
    ASSUME_ROLE_ARN   = "arn:aws:iam::${each.value.id}:role/OrganizationAccountAccessRole"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].generation,
      metadata[0].resource_version
    ]
  }
}

# Create a master ConfigMap with all accounts
resource "kubernetes_config_map" "all_accounts" {
  metadata {
    name      = "aws-accounts-registry"
    namespace = "crossplane-system"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "multi-account-setup"
    }
  }

  data = {
    for key, account in aws_organizations_account.accounts :
    key => jsonencode({
      id          = account.id
      name        = account.name
      environment = var.accounts[key].environment
      role_arn    = "arn:aws:iam::${account.id}:role/OrganizationAccountAccessRole"
    })
  }
}