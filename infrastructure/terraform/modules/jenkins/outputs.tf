output "jenkins_url" {
  description = "Jenkins 服务访问地址"
  value       = helm_release.jenkins.status == "deployed" ? "http://jenkins.${var.namespace}.svc.cluster.local:8080" : ""
}

output "jenkins_namespace" {
  description = "Jenkins 命名空间"
  value       = kubernetes_namespace.jenkins.metadata[0].name
}
