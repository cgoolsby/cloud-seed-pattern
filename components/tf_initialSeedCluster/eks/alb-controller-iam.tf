# IAM policy for AWS Load Balancer Controller
data "http" "alb_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.6.0/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "alb_controller_policy" {
  name   = "${var.cluster_name}-AWSLoadBalancerControllerIAMPolicy"
  policy = data.http.alb_controller_policy.response_body
}

# IAM role for AWS Load Balancer Controller
data "aws_iam_policy_document" "alb_controller_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      identifiers = [module.eks.oidc_provider_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "alb_controller_role" {
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume_role.json
  name               = "${var.cluster_name}-AmazonEKSLoadBalancerControllerRole"
}

resource "aws_iam_role_policy_attachment" "alb_controller_policy_attachment" {
  policy_arn = aws_iam_policy.alb_controller_policy.arn
  role       = aws_iam_role.alb_controller_role.name
}

# Output the role ARN
output "alb_controller_role_arn" {
  description = "ARN of IAM role for AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller_role.arn
}