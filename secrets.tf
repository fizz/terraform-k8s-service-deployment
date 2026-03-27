# Kubernetes Secrets via External Secrets Operator
#
# Creates an ExternalSecret CR that tells ESO to sync values from
# AWS SSM Parameter Store into a Kubernetes Secret automatically.
# The ClusterSecretStore "aws-ssm" is provisioned by eks-addons.

locals {
  has_ssm_secrets        = length(var.ssm_secrets) > 0
  has_feature_flag_find  = var.ssm_feature_flag_prefix != ""
  create_external_secret = local.has_ssm_secrets
}

# -----------------------------------------------------------------------------
# ExternalSecret — SSM → K8s Secret (via ESO)
# -----------------------------------------------------------------------------
resource "kubernetes_manifest" "external_secret" {
  count = local.create_external_secret ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "${var.service_name}-secrets"
      namespace = var.namespace
      labels = {
        app    = var.service_name
        tenant = var.tenant_name
      }
    }
    spec = merge(
      {
        refreshInterval = "1h"
        secretStoreRef = {
          name = "aws-ssm"
          kind = "ClusterSecretStore"
        }
        target = {
          name = "${var.service_name}-secrets"
        }
      },
      # Individual SSM key→value mappings
      local.has_ssm_secrets ? {
        data = [
          for env_var, ssm_path in var.ssm_secrets : {
            secretKey = env_var
            remoteRef = {
              key = ssm_path
            }
          }
        ]
      } : {},
    )
  }
}

# -----------------------------------------------------------------------------
# Feature Flags — separate ExternalSecret for wildcard discovery
# Discovered FEATURE_FLAG_* params are loaded via envFrom on the deployment,
# so new flags only require an SSM put-parameter — no terraform changes.
# -----------------------------------------------------------------------------
resource "kubernetes_manifest" "feature_flags_secret" {
  count = local.has_feature_flag_find ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "${var.service_name}-feature-flags"
      namespace = var.namespace
      labels = {
        app    = var.service_name
        tenant = var.tenant_name
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-ssm"
        kind = "ClusterSecretStore"
      }
      target = {
        name = "${var.service_name}-feature-flags"
      }
      dataFrom = [
        {
          find = {
            path = var.ssm_feature_flag_prefix
            name = {
              regexp = "FEATURE_FLAG_"
            }
            conversionStrategy = "Default"
            decodingStrategy   = "None"
          }
          rewrite = [
            {
              regexp = {
                source = ".*/(FEATURE_FLAG_.*)"
                target = "$1"
              }
            }
          ]
        }
      ]
    }
  }
}
