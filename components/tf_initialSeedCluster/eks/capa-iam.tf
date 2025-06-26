# IAM Role for Cluster API Provider AWS (CAPA)
resource "aws_iam_role" "capa_controller" {
  name = "${var.cluster_name}-capa-controller-role"

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
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:capa-system:capa-controller-manager"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Policy for CAPA controller to manage AWS resources
resource "aws_iam_role_policy" "capa_controller" {
  name = "${var.cluster_name}-capa-controller-policy"
  role = aws_iam_role.capa_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "elasticloadbalancing:*",
          "autoscaling:*",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfiles",
          "iam:ListInstanceProfilesForRole",
          "iam:AddRoleToInstanceProfile",
          "iam:PassRole",
          "iam:CreateServiceLinkedRole",
          "iam:DetachRolePolicy",
          "iam:AttachRolePolicy",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviders",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "secretsmanager:CreateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:DescribeSecret",
          "ssm:GetParameter",
          "eks:*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = "arn:aws:iam::*:role/OrganizationAccountAccessRole"
      }
    ]
  })
}

output "capa_controller_role_arn" {
  description = "ARN of the CAPA controller IAM role"
  value       = aws_iam_role.capa_controller.arn
}