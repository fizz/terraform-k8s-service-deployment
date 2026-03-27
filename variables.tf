# K8s Service Deployment Module Variables
#
# Reusable module for deploying containerized services to EKS with:
#   - IRSA for AWS service access
#   - Secrets from SSM Parameter Store
#   - ALB Ingress with shared group
#   - CMMC Level 2 compliant security context

# -----------------------------------------------------------------------------
# Service Identity
# -----------------------------------------------------------------------------
variable "service_name" {
  description = "Name of the service (e.g., 'apiserver', 'auth-handler')"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.service_name)) && length(var.service_name) >= 2 && length(var.service_name) <= 30
    error_message = "Service name must be 2-30 characters, lowercase alphanumeric with hyphens, starting with a letter."
  }
}

variable "tenant_name" {
  description = "Tenant name for resource naming and tagging"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.tenant_name)) && length(var.tenant_name) >= 2 && length(var.tenant_name) <= 30
    error_message = "Tenant name must be 2-30 characters, lowercase alphanumeric with hyphens, starting with a letter."
  }
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into"
  type        = string
}

# -----------------------------------------------------------------------------
# Container Configuration
# -----------------------------------------------------------------------------
variable "image_repository" {
  description = "ECR repository URL (e.g., '012345678901.dkr.ecr.us-east-1.amazonaws.com/my-apiserver')"
  type        = string
}

variable "image_tag" {
  description = "Container image tag (e.g., 'main-42'). No 'latest' tags allowed."
  type        = string

  validation {
    condition     = var.image_tag != "latest" && length(var.image_tag) > 0
    error_message = "Image tag must be specified and cannot be 'latest'. Use immutable tags like 'main-42'."
  }
}

variable "image_digest" {
  description = "Image digest (sha256:...). When set, image is pinned by digest for immutability."
  type        = string
  default     = ""
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8000
}

variable "command" {
  description = "Override container entrypoint (optional)"
  type        = list(string)
  default     = null
}

variable "args" {
  description = "Override container args (optional)"
  type        = list(string)
  default     = null
}

variable "replicas" {
  description = "Number of pod replicas"
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# Resource Limits
# -----------------------------------------------------------------------------
variable "resources" {
  description = "Container resource requests and limits"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

# -----------------------------------------------------------------------------
# Health Checks
# -----------------------------------------------------------------------------
variable "health_check_path" {
  description = "HTTP path for liveness and readiness probes"
  type        = string
  default     = "/health"
}

variable "liveness_probe" {
  description = "Liveness probe configuration"
  type = object({
    initial_delay_seconds = number
    period_seconds        = number
    timeout_seconds       = number
    failure_threshold     = number
  })
  default = {
    initial_delay_seconds = 15
    period_seconds        = 10
    timeout_seconds       = 5
    failure_threshold     = 3
  }
}

variable "readiness_probe" {
  description = "Readiness probe configuration"
  type = object({
    initial_delay_seconds = number
    period_seconds        = number
    timeout_seconds       = number
    failure_threshold     = number
  })
  default = {
    initial_delay_seconds = 5
    period_seconds        = 5
    timeout_seconds       = 3
    failure_threshold     = 3
  }
}


variable "startup_probe" {
  description = "Startup probe configuration"
  type = object({
    period_seconds    = number
    timeout_seconds   = number
    failure_threshold = number
  })
  default = {
    failure_threshold = 60
    timeout_seconds   = 2
    period_seconds    = 5
  }
}

# -----------------------------------------------------------------------------
# Ingress Configuration
# -----------------------------------------------------------------------------
variable "ingress_hostname" {
  description = "Hostname for ingress (e.g., 'app.demo.ramparts.dev')"
  type        = string
}

variable "ingress_paths" {
  description = "List of paths to route to this service"
  type        = list(string)
  default     = ["/"]
}

variable "certificate_arn" {
  description = "ARN of ACM certificate for HTTPS"
  type        = string
}

variable "alb_group_name" {
  description = "ALB ingress group name for sharing ALB across services"
  type        = string
  default     = "shared"
}

# -----------------------------------------------------------------------------
# IRSA Configuration
# -----------------------------------------------------------------------------
variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider (with https://)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# Secrets (from SSM Parameter Store)
# -----------------------------------------------------------------------------
variable "ssm_secrets" {
  description = "Map of environment variable names to SSM parameter paths"
  type        = map(string)
  default     = {}
}

variable "ssm_feature_flag_prefix" {
  description = "SSM path prefix for feature flag discovery via ESO dataFrom.find"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Additional IAM Policies
# -----------------------------------------------------------------------------
variable "irsa_policy_arns" {
  description = "List of IAM policy ARNs to attach to the IRSA role"
  type        = list(string)
  default     = []
}

variable "irsa_inline_policies" {
  description = "Map of inline policy names to policy JSON documents"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Environment Variables
# -----------------------------------------------------------------------------
variable "environment_variables" {
  description = "Map of non-secret environment variables"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Optional Volume Mounts
# -----------------------------------------------------------------------------
variable "tmp_volume_enabled" {
  description = "Enable /tmp emptyDir volume for read-only root filesystem"
  type        = bool
  default     = true
}

variable "extra_volumes" {
  description = "Additional volumes to mount"
  type = list(object({
    name       = string
    mount_path = string
    empty_dir  = optional(bool, true)
    config_map = optional(string)
    secret     = optional(string)
    read_only  = optional(bool, false)
  }))
  default = []
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------
variable "tags" {
  description = "Additional tags to apply to AWS resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Liveness probe enabled
# -----------------------------------------------------------------------------
variable "liveness_probe_enabled" {
  description = "Whether liveness probe is enabled or not"
  type        = bool
  default     = true
}


# -----------------------------------------------------------------------------
# Readiness probe enabled
# -----------------------------------------------------------------------------
variable "readiness_probe_enabled" {
  description = "Whether readiness probe is enabled or not"
  type        = bool
  default     = true
}


# -----------------------------------------------------------------------------
# Startup probe enabled
# -----------------------------------------------------------------------------
variable "startup_probe_enabled" {
  description = "Whether startup probe is enabled or not"
  type        = bool
  default     = false
}
