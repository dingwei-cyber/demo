/**
 * Jenkins 模块 - 通过 Helm 部署 Jenkins 到 Kubernetes
 */

# 创建命名空间
resource "kubernetes_namespace" "jenkins" {
  metadata {
    name = var.namespace
    labels = {
      name = var.namespace
    }
  }
}

# Jenkins 配置密钥
resource "kubernetes_secret" "jenkins_secrets" {
  metadata {
    name      = "jenkins-secrets"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  data = {
    JENKINS_ADMIN_PASSWORD = var.jenkins_admin_password
    HARBOR_URL             = var.harbor_url
    HARBOR_USERNAME        = var.harbor_username
    HARBOR_PASSWORD        = var.harbor_password
    GITLAB_URL             = var.gitlab_url
    GITLAB_TOKEN           = var.gitlab_token
    SONARQUBE_URL          = var.sonarqube_url
    SONARQUBE_TOKEN        = var.sonarqube_token
  }

  type = "Opaque"
}

# JCasC ConfigMap
resource "kubernetes_config_map" "jenkins_casc" {
  metadata {
    name      = "jenkins-casc"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  data = {
    "jenkins.yaml" = file("${path.root}/../../jenkins/casc/jenkins.yaml")
  }
}

# Jenkins RBAC - ServiceAccount
resource "kubernetes_service_account" "jenkins" {
  metadata {
    name      = "jenkins"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }
}

# Jenkins RBAC - ClusterRole（允许管理 Pod 用于弹性 Agent）
resource "kubernetes_cluster_role" "jenkins" {
  metadata {
    name = "jenkins-agent-role"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/exec", "pods/log", "services", "endpoints", "persistentvolumeclaims", "events", "configmaps", "secrets"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets"]
    verbs      = ["get", "list", "watch"]
  }
}

# Jenkins RBAC - ClusterRoleBinding
resource "kubernetes_cluster_role_binding" "jenkins" {
  metadata {
    name = "jenkins-agent-rolebinding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.jenkins.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.jenkins.metadata[0].name
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }
}

# 部署 Jenkins（Helm）
resource "helm_release" "jenkins" {
  name       = "jenkins"
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  namespace  = kubernetes_namespace.jenkins.metadata[0].name
  version    = "5.1.0"

  wait    = true
  timeout = 600

  values = [
    templatefile("${path.module}/jenkins-values.yaml.tpl", {
      storage_size     = var.jenkins_storage_size
      jenkins_url      = var.jenkins_url
      casc_config_map  = kubernetes_config_map.jenkins_casc.metadata[0].name
      secrets_name     = kubernetes_secret.jenkins_secrets.metadata[0].name
    })
  ]

  depends_on = [
    kubernetes_service_account.jenkins,
    kubernetes_cluster_role_binding.jenkins,
    kubernetes_config_map.jenkins_casc,
    kubernetes_secret.jenkins_secrets
  ]
}
