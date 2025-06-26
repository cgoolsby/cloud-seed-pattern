# IAM role for Crossplane AWS Provider
resource "aws_iam_role" "crossplane_aws_provider" {
  name = "${var.cluster_name}-CrossplaneAWSProviderRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:crossplane-system:provider-aws-*"
          }
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Policy for Crossplane to manage AWS resources
resource "aws_iam_role_policy_attachment" "crossplane_aws_provider_admin" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.crossplane_aws_provider.name
}

# Output the role ARN for reference
output "crossplane_aws_provider_role_arn" {
  value = aws_iam_role.crossplane_aws_provider.arn
  description = "ARN of the IAM role for Crossplane AWS Provider"
}