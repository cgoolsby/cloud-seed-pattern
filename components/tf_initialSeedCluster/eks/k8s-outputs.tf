# Create ConfigMap for Terraform outputs
resource "kubernetes_config_map" "terraform_outputs" {
  metadata {
    name      = "terraform-outputs"
    namespace = "flux-system"
  }

  data = {
    AWS_ACCOUNT_ID                = data.aws_caller_identity.current.account_id
    EBS_CSI_ROLE_ARN              = aws_iam_role.ebs_csi_role.arn
    EFS_CSI_ROLE_ARN              = aws_iam_role.efs_csi_role.arn
    EXTERNAL_SECRETS_ROLE_ARN     = aws_iam_role.external_secrets_role.arn
    ALB_CONTROLLER_ROLE_ARN       = aws_iam_role.alb_controller_role.arn
    CLUSTER_NAME                  = var.cluster_name
    CLUSTER_ENDPOINT              = module.eks.cluster_endpoint
    VPC_ID                        = module.vpc.vpc_id
  }

  lifecycle {
    # Only ignore changes that would prevent deletion, not data updates
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels,
      metadata[0].generation,
      metadata[0].resource_version
    ]
    prevent_destroy = false
  }

  depends_on = [
    module.eks,
    null_resource.create_flux_ns
  ]
}
