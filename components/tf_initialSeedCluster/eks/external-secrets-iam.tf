data "aws_iam_policy_document" "external_secrets_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values = [
        "system:serviceaccount:external-secrets:external-secrets-sa",
        "system:serviceaccount:external-secrets:external-secrets-webhook-sa",
        "system:serviceaccount:external-secrets:external-secrets-cert-controller-sa",
        "system:serviceaccount:supabase:supabase-sa"
      ]
    }

    principals {
      identifiers = [module.eks.oidc_provider_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "external_secrets_role" {
  assume_role_policy = data.aws_iam_policy_document.external_secrets_assume_role.json
  name               = "ExternalSecretsOperatorRole"
}

resource "aws_iam_policy" "external_secrets_policy" {
  name = "ExternalSecretsOperatorPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParameterHistory",
          "ssm:GetParametersByPath"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets_policy_attachment" {
  policy_arn = aws_iam_policy.external_secrets_policy.arn
  role       = aws_iam_role.external_secrets_role.name
}