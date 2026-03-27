# k8s-service-deployment

Terraform module for deploying containerized services to Amazon EKS with CMMC Level 2 compliant security configurations.

## Description

This module provides a standardized, secure deployment pattern for Kubernetes services on EKS. It creates all necessary resources for running a containerized application with:

- IRSA (IAM Roles for Service Accounts) for secure AWS service access
- Secrets management via AWS SSM Parameter Store
- ALB Ingress with shared load balancer support
- Hardened security contexts meeting CMMC Level 2 requirements

## Resources Created

| Resource | Description |
|----------|-------------|
| `kubernetes_deployment_v1` | Kubernetes Deployment with security-hardened pod spec |
| `kubernetes_service_v1` | ClusterIP Service exposing the deployment |
| `kubernetes_ingress_v1` | ALB Ingress for external HTTPS access |
| `kubernetes_service_account_v1` | Service account with IRSA annotation |
| `kubernetes_secret_v1` | Kubernetes Secret populated from SSM (conditional) |
| `aws_iam_role` | IAM role for IRSA with OIDC trust policy |
| `aws_iam_role_policy` | SSM read policy and inline policies |
| `aws_iam_role_policy_attachment` | Managed policy attachments |

## Usage

```hcl
module "apiserver" {
  source = "../modules/k8s-service-deployment"

  # Service Identity
  service_name = "apiserver"
  tenant_name  = "tenant-momcorp-abc123"
  namespace    = "ramparts-app"

  # Container Configuration
  image_repository = "012345678901.dkr.ecr.us-east-1.amazonaws.com/ramparts-apiserver"
  image_tag        = "main-42"
  image_digest     = "sha256:abc123..."  # Pin by digest for CKV_K8S_43 compliance
  container_port   = 8000
  replicas         = 2

  # Resource Limits
  resources = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }

  # Health Checks
  health_check_path = "/health"

  # Ingress Configuration
  ingress_hostname = "app.demo.ramparts.dev"
  ingress_paths    = ["/api", "/graphql"]
  certificate_arn  = "arn:aws:acm:us-east-1:012345678901:certificate/abc123"
  alb_group_name   = "shared"

  # IRSA Configuration
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  account_id        = data.aws_caller_identity.current.account_id
  region            = "us-east-1"

  # Secrets from SSM Parameter Store
  ssm_secrets = {
    DATABASE_URL = "/ramparts/demo/database-url"
    API_KEY      = "/ramparts/demo/api-key"
  }

  # Environment Variables
  environment_variables = {
    LOG_LEVEL   = "info"
    ENVIRONMENT = "production"
  }

  # Additional IAM Policies
  irsa_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  ]

  tags = {
    Environment = "production"
    Project     = "ramparts"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `service_name` | Name of the service (2-30 chars, lowercase alphanumeric with hyphens) | `string` | n/a | yes |
| `tenant_name` | Tenant name for resource naming and tagging | `string` | n/a | yes |
| `namespace` | Kubernetes namespace to deploy into | `string` | n/a | yes |
| `image_repository` | ECR repository URL | `string` | n/a | yes |
| `image_tag` | Container image tag (cannot be 'latest') | `string` | n/a | yes |
| `image_digest` | Image digest (sha256:...) for immutable pinning | `string` | `""` | no |
| `ingress_hostname` | Hostname for ingress | `string` | n/a | yes |
| `certificate_arn` | ARN of ACM certificate for HTTPS | `string` | n/a | yes |
| `oidc_provider_arn` | ARN of the EKS OIDC provider | `string` | n/a | yes |
| `oidc_provider_url` | URL of the EKS OIDC provider (with https://) | `string` | n/a | yes |
| `account_id` | AWS account ID | `string` | n/a | yes |
| `container_port` | Port the container listens on | `number` | `8000` | no |
| `replicas` | Number of pod replicas | `number` | `1` | no |
| `resources` | Container resource requests and limits | `object` | See below | no |
| `health_check_path` | HTTP path for liveness and readiness probes | `string` | `"/health"` | no |
| `liveness_probe` | Liveness probe configuration | `object` | See below | no |
| `readiness_probe` | Readiness probe configuration | `object` | See below | no |
| `ingress_paths` | List of paths to route to this service | `list(string)` | `["/"]` | no |
| `alb_group_name` | ALB ingress group name for sharing ALB | `string` | `"shared"` | no |
| `region` | AWS region | `string` | `"us-east-1"` | no |
| `ssm_secrets` | Map of environment variable names to SSM parameter paths | `map(string)` | `{}` | no |
| `irsa_policy_arns` | List of IAM policy ARNs to attach to the IRSA role | `list(string)` | `[]` | no |
| `irsa_inline_policies` | Map of inline policy names to policy JSON documents | `map(string)` | `{}` | no |
| `environment_variables` | Map of non-secret environment variables | `map(string)` | `{}` | no |
| `tmp_volume_enabled` | Enable /tmp emptyDir volume for read-only root filesystem | `bool` | `true` | no |
| `extra_volumes` | Additional volumes to mount | `list(object)` | `[]` | no |
| `tags` | Additional tags to apply to AWS resources | `map(string)` | `{}` | no |

### Default Values for Complex Types

**resources:**
```hcl
{
  requests = {
    cpu    = "100m"
    memory = "128Mi"
  }
  limits = {
    cpu    = "500m"
    memory = "512Mi"
  }
}
```

**liveness_probe:**
```hcl
{
  initial_delay_seconds = 15
  period_seconds        = 10
  timeout_seconds       = 5
  failure_threshold     = 3
}
```

**readiness_probe:**
```hcl
{
  initial_delay_seconds = 5
  period_seconds        = 5
  timeout_seconds       = 3
  failure_threshold     = 3
}
```

**extra_volumes:**
```hcl
[
  {
    name       = string
    mount_path = string
    empty_dir  = optional(bool, true)
    config_map = optional(string)
    secret     = optional(string)
    read_only  = optional(bool, false)
  }
]
```

## Outputs

| Name | Description |
|------|-------------|
| `service_account_name` | Name of the Kubernetes service account |
| `irsa_role_arn` | ARN of the IRSA IAM role |
| `irsa_role_name` | Name of the IRSA IAM role |
| `deployment_name` | Name of the Kubernetes deployment |
| `service_name` | Name of the Kubernetes service |
| `ingress_name` | Name of the Kubernetes ingress |
| `secret_name` | Name of the Kubernetes secret (null if no secrets configured) |

## CMMC Level 2 Compliance

This module implements security controls required for CMMC Level 2 compliance:

### Pod Security Context
- Runs as non-root user (UID 1000)
- Uses RuntimeDefault seccomp profile
- Sets fs_group for consistent file permissions

### Container Security Context
- `allowPrivilegeEscalation: false` - Prevents privilege escalation attacks
- `readOnlyRootFilesystem: true` - Immutable container filesystem
- `runAsNonRoot: true` - Enforces non-root execution
- `capabilities.drop: ["ALL"]` - Drops all Linux capabilities

### Checkov Policy Compliance
The module addresses the following Checkov policies:
- **CKV_K8S_8**: Liveness probe configured
- **CKV_K8S_9**: Readiness probe configured
- **CKV_K8S_11**: CPU limits set
- **CKV_K8S_12**: Memory limits set
- **CKV_K8S_13**: Memory requests set
- **CKV_K8S_15**: Image pull policy set to Always
- **CKV_K8S_28**: Privilege escalation disabled
- **CKV_K8S_29**: Pod-level security context applied
- **CKV_K8S_30**: Seccomp profile configured
- **CKV_K8S_43**: Image pinned by digest when `image_digest` is provided

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |
| kubernetes | >= 2.0 |

## Notes

- The `image_tag` variable does not accept `latest` to ensure immutable, auditable deployments
- When `image_digest` is provided, the image reference becomes `repo:tag@digest` for full immutability (tag for humans, digest for machines)
- To look up a digest:
  ```bash
  # ECR image
  aws ecr describe-images --repository-name my-apiserver \
    --image-ids imageTag=<commit-sha> \
    --query 'imageDetails[0].imageDigest' --output text

  # Docker Hub image
  docker manifest inspect ealen/echo-server:0.9.2 | jq -r '.manifests[0].digest'
  ```
- When `ssm_secrets` is configured, the module automatically creates IAM policies for SSM and KMS access
- The ALB is shared across services using the `alb_group_name` to reduce costs and simplify DNS management
- A `/tmp` emptyDir volume is mounted by default to support read-only root filesystem requirements
- Rolling updates are triggered automatically when secret values change (via checksum annotation)
