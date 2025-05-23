# k8sHyperscalar Kubernetes Resources

This directory contains declarative Kubernetes resources managed by Flux for provisioning and configuring both infrastructure (via Crossplane) and Kubernetes clusters (via Cluster API).

## Directory Structure

```
kubernetes/
├── base/                   # Base components installed by Flux
│   ├── cluster-api/        # Cluster API core controllers and CRDs
│   ├── crossplane/         # Crossplane core, providers, and compositions
│   └── ...
├── clusters/               # Cluster API cluster declarations
│   ├── templates/          # Reusable cluster templates
│   ├── production/         # Production cluster declarations
│   ├── staging/            # Staging cluster declarations
│   └── development/        # Development cluster declarations
└── infrastructure/         # Crossplane infrastructure declarations
    ├── aws/                # AWS-specific resources (VPCs, IAM, etc.)
    ├── networking/         # Network infrastructure components
    ├── services/           # Shared services infrastructure
    └── templates/          # Reusable infrastructure templates
```

## Usage

### Creating a New Cluster

1. Copy a template from `clusters/templates/` to the appropriate environment directory
2. Customize the cluster parameters
3. Add the new file to the corresponding kustomization.yaml

Example:
```bash
cp kubernetes/clusters/templates/cluster-template.yaml kubernetes/clusters/development/my-dev-cluster.yaml
# Edit my-dev-cluster.yaml with appropriate values
```

### Creating Infrastructure Resources

1. Copy a template from `infrastructure/templates/` to the appropriate directory
2. Customize the infrastructure parameters
3. Add the new file to the corresponding kustomization.yaml

Example:
```bash
cp kubernetes/infrastructure/templates/vpc-claim.yaml kubernetes/infrastructure/aws/vpc/prod-vpc.yaml
# Edit prod-vpc.yaml with appropriate values
```

## Parameter Substitution

Templates use placeholder variables (e.g., ${CLUSTER_NAME}) that should be replaced with actual values when creating resources. This can be done manually or with a script for automation.

## Multi-Account Strategy

This repository supports automated multi-account AWS deployments:

### Account Creation
1. **Terraform Setup**: Use `terraform/accounts/` to create AWS accounts via Organizations
2. **Auto-Generated ConfigMaps**: Each account gets a ConfigMap with account details in `crossplane-system` namespace
3. **ProviderConfigs**: Create ProviderConfigs that reference the ConfigMaps for cross-account access

### Account Usage
```yaml
# Example ProviderConfig for a development account
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: dev-account
spec:
  credentials:
    source: InjectedIdentity
  assumeRoleARN: "arn:aws:iam::ACCOUNT-ID:role/OrganizationAccountAccessRole"
```

### Resource Targeting
```yaml
# Example VPC in specific account
apiVersion: network.example.org/v1alpha1
kind: VPC
metadata:
  name: dev-vpc
spec:
  accountName: dev-account  # References the ProviderConfig
  region: us-east-1
  cidrBlock: "10.1.0.0/16"
```

## IRSA Authentication

All Crossplane operations use IAM Roles for Service Accounts (IRSA):
- **No static credentials** stored in the cluster
- **Cross-account access** via OrganizationAccountAccessRole
- **Automatic token rotation** handled by AWS STS

## Integration with Frontend GUI

For teams looking to consume these resources via a GUI:
- Create clusters/infrastructure using the templates
- Store template parameters in a database
- Reference account ConfigMaps to populate account dropdown lists
- Generate the YAML files dynamically based on user input
- Apply the resources using Kubernetes API or GitOps workflows
