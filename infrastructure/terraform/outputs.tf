# ============================================================
# Terraform 输出值
# ============================================================

output "cluster_endpoint" {
  description = "Kubernetes API Server 地址"
  value       = module.k8s_cluster.cluster_endpoint
}

output "cluster_name" {
  description = "Kubernetes 集群名称"
  value       = module.k8s_cluster.cluster_name
}

output "kubeconfig_command" {
  description = "获取 kubeconfig 的命令"
  value       = module.k8s_cluster.kubeconfig_command
}

output "jenkins_url" {
  description = "Jenkins 访问地址"
  value       = module.jenkins.jenkins_url
}

output "jenkins_namespace" {
  description = "Jenkins 命名空间"
  value       = "jenkins"
}
