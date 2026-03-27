# IRSA (IAM Roles for Service Accounts) Configuration
#
# Creates:
#   - IAM role with OIDC trust policy for the K8s service account
#   - SSM read policy for accessing secrets
#   - Attachments for additional managed policies
#   - Inline policies for custom permissions

# Partition-aware: resolves to "aws" in commercial, "aws-us-gov" in GovCloud
data "aws_partition" "current" {}

locals {
  oidc_issuer     = replace(var.oidc_provider_url, "https://", "")
  service_account = "${var.service_name}-sa"
  role_name       = "${var.service_name}-${var.tenant_name}"
}

# -----------------------------------------------------------------------------
# IRSA Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "service" {
  name = local.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = "system:serviceaccount:${var.namespace}:${local.service_account}"
        }
      }
    }]
  })

  tags = merge(var.tags, {
    Name       = local.role_name
    Service    = var.service_name
    Tenant     = var.tenant_name
    ManagedBy  = "terraform"
    Compliance = "cmmc-l2"
  })
}

# -----------------------------------------------------------------------------
# SSM Parameter Store Read Policy (for secrets)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "ssm_read" {
  count = length(var.ssm_secrets) > 0 ? 1 : 0

  name = "ssm-secrets-read"
  role = aws_iam_role.service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMGetParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          for path in values(var.ssm_secrets) :
          "arn:${data.aws_partition.current.partition}:ssm:${var.region}:${var.account_id}:parameter${path}"
        ]
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:ViaService" = "ssm.${var.region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Managed Policy Attachments
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.irsa_policy_arns)

  role       = aws_iam_role.service.name
  policy_arn = each.value
}

# -----------------------------------------------------------------------------
# Inline Policies
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "inline" {
  for_each = var.irsa_inline_policies

  name   = each.key
  role   = aws_iam_role.service.id
  policy = each.value
}

# -----------------------------------------------------------------------------
# Kubernetes Service Account
# -----------------------------------------------------------------------------
resource "kubernetes_service_account_v1" "service" {
  metadata {
    name      = local.service_account
    namespace = var.namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.service.arn
    }

    labels = {
      app    = var.service_name
      tenant = var.tenant_name
    }
  }
}
