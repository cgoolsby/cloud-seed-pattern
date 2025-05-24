# Test Cluster Configurations

This directory contains test cluster configurations for validating our multi-account setup.

## Prerequisites for Child Accounts

When creating clusters in child AWS accounts, certain IAM resources must exist:

### For Self-Managed Clusters (test-cluster.yaml)
- Instance profiles: `control-plane.cluster-api-provider-aws.sigs.k8s.io` and `nodes.cluster-api-provider-aws.sigs.k8s.io`
- Or remove `iamInstanceProfile` fields and use default EC2 roles

### For EKS Managed Clusters (test-eks-cluster.yaml)
- EKS service role: `eks-controlplane.cluster-api-provider-aws.sigs.k8s.io`
- EKS node group role: `eks-nodegroup.cluster-api-provider-aws.sigs.k8s.io`

These can be created via Terraform or manually in the AWS console.

## Cluster Types

### test-cluster.yaml
- Uses Cluster API with kubeadm for full control
- Requires more IAM setup
- More flexibility but more operational overhead

### test-eks-cluster.yaml
- Uses EKS managed control plane and node groups
- Simpler IAM requirements once roles exist
- Less flexibility but easier to manage

## Using Existing VPC

Both configurations use the existing VPC created by Crossplane:
- VPC ID: `vpc-024c10ffcc74e11e5`
- Region: `us-west-2`
- Account: `137457118074` (test-account-1)

The VPC includes:
- 3 public subnets (for load balancers)
- 3 private subnets (for worker nodes)
- NAT Gateway for outbound connectivity
- Proper tagging for Kubernetes