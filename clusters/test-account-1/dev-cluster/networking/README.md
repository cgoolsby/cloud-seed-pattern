# Networking Configuration

This directory contains the networking resources for a cluster, primarily the VPC and subnet configuration using Crossplane.

## Resources

1. **vpc.yaml** - Creates a VPC with public and private subnets across two availability zones
2. **networking-configmap.yaml** - Stores networking values for use by cluster definitions

## Configuration

The following variables need to be set when using this template:

- `${CLUSTER_NAME}` - Name of the cluster
- `${ACCOUNT_NAMESPACE}` - Namespace for the account (e.g., aws-test-account-1)
- `${ACCOUNT_NAME}` - Account alias for the ProviderConfig
- `${REGION}` - AWS region (e.g., us-east-1)
- `${VPC_CIDR}` - VPC CIDR block (e.g., 10.0.0.0/16)
- `${PUBLIC_SUBNET_A_CIDR}` - Public subnet A CIDR (e.g., 10.0.1.0/24)
- `${PUBLIC_SUBNET_B_CIDR}` - Public subnet B CIDR (e.g., 10.0.2.0/24)
- `${PRIVATE_SUBNET_A_CIDR}` - Private subnet A CIDR (e.g., 10.0.10.0/24)
- `${PRIVATE_SUBNET_B_CIDR}` - Private subnet B CIDR (e.g., 10.0.11.0/24)
- `${ENVIRONMENT}` - Environment tag (e.g., dev, staging, prod)

## Usage

The VPC resource will:
- Create a VPC with DNS support and hostnames enabled
- Create 2 public and 2 private subnets
- Create NAT gateways (one per AZ for high availability)
- Tag all resources appropriately for Kubernetes cluster discovery

The networking ConfigMaps will be populated with the created resource IDs once Crossplane provisions the infrastructure.