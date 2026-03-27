# Example: Deploy an API server for the momcorp tenant

data "aws_caller_identity" "current" {}

module "apiserver" {
  source = "../../"

  # Service Identity
  service_name = "apiserver"
  tenant_name  = "tenant-momcorp-abc123"
  namespace    = "tenant-momcorp-abc123"

  # Container Configuration
  image_repository = "${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-1.amazonaws.com/ramparts-apiserver"
  image_tag        = "main-42"
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
  ingress_hostname = "app.momcorp.ramparts.dev"
  ingress_paths    = ["/"]
  certificate_arn  = "arn:aws:acm:us-east-1:012345678901:certificate/example-cert-id"
  alb_group_name   = "shared"

  # IRSA Configuration
  oidc_provider_arn = "arn:aws:iam::012345678901:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  oidc_provider_url = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  account_id        = data.aws_caller_identity.current.account_id
  region            = "us-east-1"

  # Secrets from SSM Parameter Store
  ssm_secrets = {
    DATABASE_URL = "/ramparts/dev/tenants/momcorp/apiserver/database-url"
    API_KEY      = "/ramparts/dev/tenants/momcorp/apiserver/api-key"
  }

  # Feature flags — new flags appear via SSM without terraform changes
  ssm_feature_flag_prefix = "/ramparts/dev/tenants/momcorp/apiserver/feature-flags/"

  # Environment Variables
  environment_variables = {
    LOG_LEVEL   = "info"
    ENVIRONMENT = "dev"
    TENANT_NAME = "momcorp"
  }

  tags = {
    Environment = "dev"
    Tenant      = "momcorp"
  }
}

output "irsa_role_arn" {
  value = module.apiserver.irsa_role_arn
}

output "service_url" {
  value = "https://app.momcorp.ramparts.dev"
}
