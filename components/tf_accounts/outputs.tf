output "account_ids" {
  description = "Map of account aliases to account IDs"
  value = {
    for key, account in aws_organizations_account.accounts :
    key => account.id
  }
}

output "organization_id" {
  description = "The ID of the AWS Organization"
  value = try(aws_organizations_organization.org[0].id, "not-created")
}

output "organization_arn" {
  description = "The ARN of the AWS Organization"
  value = try(aws_organizations_organization.org[0].arn, "not-created")
}

output "configmap_names" {
  description = "Names of created ConfigMaps for each account"
  value = {
    for key, _ in aws_organizations_account.accounts :
    key => "aws-account-${key}"
  }
}