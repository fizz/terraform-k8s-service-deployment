# K8s Service Deployment Module
#
# Creates Kubernetes Deployment, Service, and Ingress for a containerized service.
# Designed for CMMC Level 2 compliance with hardened security contexts.
#
# Resources:
#   - Kubernetes Deployment with security context
#   - Kubernetes Service (ClusterIP)
#   - Kubernetes Ingress (ALB)

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
  }
}

locals {
  labels = {
    app     = var.service_name
    tenant  = var.tenant_name
    version = var.image_tag
  }

  # Compute ingress annotations based on path requirements
  ingress_annotations = {
    "alb.ingress.kubernetes.io/group.name"       = var.alb_group_name
    "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
    "alb.ingress.kubernetes.io/target-type"      = "ip"
    "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTPS\": 443}]"
    "alb.ingress.kubernetes.io/certificate-arn"  = var.certificate_arn
    "alb.ingress.kubernetes.io/healthcheck-path" = var.health_check_path
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Deployment
# -----------------------------------------------------------------------------
resource "kubernetes_deployment_v1" "service" {
  metadata {
    name      = var.service_name
    namespace = var.namespace

    labels = local.labels
  }

  wait_for_rollout = false

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = var.service_name
      }
    }

    template {
      metadata {
        labels = local.labels

        annotations = {
          # Force rolling update when secrets change
          "checksum/secrets" = length(var.ssm_secrets) > 0 ? sha256(jsonencode(var.ssm_secrets)) : "none"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.service.metadata[0].name

        # CKV_K8S_29: Pod-level security context (CMMC)
        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          run_as_group    = 1000
          fs_group        = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        # /tmp volume for read-only root filesystem
        dynamic "volume" {
          for_each = var.tmp_volume_enabled ? [1] : []
          content {
            name = "tmp"
            empty_dir {}
          }
        }

        # Extra volumes
        dynamic "volume" {
          for_each = var.extra_volumes
          content {
            name = volume.value.name

            dynamic "empty_dir" {
              for_each = volume.value.empty_dir == true ? [1] : []
              content {}
            }

            dynamic "config_map" {
              for_each = volume.value.config_map != null ? [1] : []
              content {
                name = volume.value.config_map
              }
            }

            dynamic "secret" {
              for_each = volume.value.secret != null ? [1] : []
              content {
                secret_name = volume.value.secret
              }
            }
          }
        }

        container {
          name  = var.service_name
          image = var.image_digest != "" ? "${var.image_repository}:${var.image_tag}@${var.image_digest}" : "${var.image_repository}:${var.image_tag}"

          # CKV_K8S_15: Always pull to ensure tag matches
          image_pull_policy = "Always"

          # Override entrypoint/args if specified
          command = var.command
          args    = var.args

          port {
            container_port = var.container_port
            protocol       = "TCP"
          }

          # Environment variables from ConfigMap/direct values
          dynamic "env" {
            for_each = var.environment_variables
            content {
              name  = env.key
              value = env.value
            }
          }

          # Environment variables from Secrets
          dynamic "env" {
            for_each = var.ssm_secrets
            content {
              name = env.key
              value_from {
                secret_key_ref {
                  name = "${var.service_name}-secrets"
                  key  = env.key
                }
              }
            }
          }

          # Feature flags — loaded via envFrom so new flags appear without terraform changes
          # from feature_flags import *
          dynamic "env_from" {
            for_each = var.ssm_feature_flag_prefix != "" ? [1] : []
            content {
              secret_ref {
                name = "${var.service_name}-feature-flags"
              }
            }
          }

          dynamic "startup_probe" {
            for_each = var.startup_probe_enabled ? [1] : []
            content {
              http_get {
                path = var.health_check_path
                port = var.container_port
              }
              period_seconds        = var.startup_probe.period_seconds
              timeout_seconds       = var.startup_probe.timeout_seconds
              failure_threshold     = var.startup_probe.failure_threshold
            }
          }

          # CKV_K8S_8: Liveness probe

          dynamic "liveness_probe" {
            for_each = var.liveness_probe_enabled ? [1] : []
            content {
              http_get {
                path = var.health_check_path
                port = var.container_port
              }
              initial_delay_seconds = var.liveness_probe.initial_delay_seconds
              period_seconds        = var.liveness_probe.period_seconds
              timeout_seconds       = var.liveness_probe.timeout_seconds
              failure_threshold     = var.liveness_probe.failure_threshold
            }
          }


          # CKV_K8S_9: Readiness probe

          dynamic "readiness_probe" {
            for_each = var.readiness_probe_enabled ? [1] : []
            content {
              http_get {
                path = var.health_check_path
                port = var.container_port
              }
              initial_delay_seconds = var.readiness_probe.initial_delay_seconds
              period_seconds        = var.readiness_probe.period_seconds
              timeout_seconds       = var.readiness_probe.timeout_seconds
              failure_threshold     = var.readiness_probe.failure_threshold
            }
          }

          # Resource limits (CKV_K8S_11, CKV_K8S_12, CKV_K8S_13)
          resources {
            requests = {
              cpu    = var.resources.requests.cpu
              memory = var.resources.requests.memory
            }
            limits = {
              cpu    = var.resources.limits.cpu
              memory = var.resources.limits.memory
            }
          }

          # CKV_K8S_28, CKV_K8S_30: Container security context (CMMC)
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 1000
            capabilities {
              drop = ["ALL"]
            }
          }

          # /tmp volume mount for read-only root filesystem
          dynamic "volume_mount" {
            for_each = var.tmp_volume_enabled ? [1] : []
            content {
              name       = "tmp"
              mount_path = "/tmp"
            }
          }

          # Extra volume mounts
          dynamic "volume_mount" {
            for_each = var.extra_volumes
            content {
              name       = volume_mount.value.name
              mount_path = volume_mount.value.mount_path
              read_only  = volume_mount.value.read_only
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # Ignore annotations added by kubectl rollout restart
      spec[0].template[0].metadata[0].annotations["kubectl.kubernetes.io/restartedAt"],
    ]
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Service
# -----------------------------------------------------------------------------
resource "kubernetes_service_v1" "service" {
  metadata {
    name      = var.service_name
    namespace = var.namespace

    labels = local.labels
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = var.service_name
    }

    port {
      port        = 80
      target_port = var.container_port
      protocol    = "TCP"
    }
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Ingress (ALB)
# -----------------------------------------------------------------------------
resource "kubernetes_ingress_v1" "service" {
  metadata {
    name      = var.service_name
    namespace = var.namespace

    labels      = local.labels
    annotations = local.ingress_annotations
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = var.ingress_hostname

      http {
        dynamic "path" {
          for_each = var.ingress_paths
          content {
            path      = path.value
            path_type = "Prefix"

            backend {
              service {
                name = kubernetes_service_v1.service.metadata[0].name
                port {
                  number = 80
                }
              }
            }
          }
        }
      }
    }
  }
}
