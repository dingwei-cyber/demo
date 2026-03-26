output "cluster_endpoint" {
  description = "EKS 集群 API Server 地址"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "集群名称"
  value       = module.eks.cluster_name
}

output "cluster_ca_certificate" {
  description = "集群 CA 证书（Base64）"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_token" {
  description = "集群认证 Token"
  value       = module.eks.cluster_token
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "OIDC Provider ARN（用于 IRSA）"
  value       = module.eks.oidc_provider_arn
}

output "kubeconfig_command" {
  description = "更新 kubeconfig 的命令"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}"
}
