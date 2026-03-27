# K8s Service Deployment Module Outputs

output "service_account_name" {
  description = "Name of the Kubernetes service account"
  value       = kubernetes_service_account_v1.service.metadata[0].name
}

output "irsa_role_arn" {
  description = "ARN of the IRSA IAM role"
  value       = aws_iam_role.service.arn
}

output "irsa_role_name" {
  description = "Name of the IRSA IAM role"
  value       = aws_iam_role.service.name
}

output "deployment_name" {
  description = "Name of the Kubernetes deployment"
  value       = kubernetes_deployment_v1.service.metadata[0].name
}

output "service_name" {
  description = "Name of the Kubernetes service"
  value       = kubernetes_service_v1.service.metadata[0].name
}

output "ingress_name" {
  description = "Name of the Kubernetes ingress"
  value       = kubernetes_ingress_v1.service.metadata[0].name
}

output "secret_name" {
  description = "Name of the Kubernetes secret (if created)"
  value       = length(var.ssm_secrets) > 0 ? "${var.service_name}-secrets" : null
}
