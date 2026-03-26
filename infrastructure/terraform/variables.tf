# ============================================================
# Terraform 变量定义
# ============================================================

# 通用配置
variable "environment" {
  description = "部署环境：dev | staging | prod"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment 必须是 dev、staging 或 prod 之一"
  }
}

variable "region" {
  description = "云服务商区域（AWS: us-east-1, 阿里云: cn-hangzhou 等）"
  type        = string
  default     = "us-east-1"
}

# ============================================================
# Kubernetes 集群配置
# ============================================================
variable "cluster_name" {
  description = "Kubernetes 集群名称"
  type        = string
  default     = "cicd-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes 版本"
  type        = string
  default     = "1.28"
}

variable "vpc_cidr" {
  description = "VPC CIDR 地址段"
  type        = string
  default     = "10.0.0.0/16"
}

variable "pod_cidr" {
  description = "Pod 网络 CIDR"
  type        = string
  default     = "172.16.0.0/16"
}

variable "service_cidr" {
  description = "Service 网络 CIDR"
  type        = string
  default     = "172.20.0.0/16"
}

# ============================================================
# 工作节点配置
# ============================================================
variable "node_count" {
  description = "通用节点初始数量"
  type        = number
  default     = 3
}

variable "node_min_count" {
  description = "通用节点最小数量（Autoscaler）"
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "通用节点最大数量（Autoscaler）"
  type        = number
  default     = 10
}

variable "node_instance_type" {
  description = "通用节点实例规格"
  type        = string
  default     = "m5.xlarge"  # AWS: 4C/16G
}

variable "node_disk_size" {
  description = "节点系统盘大小（GB）"
  type        = number
  default     = 100
}

variable "build_node_instance_type" {
  description = "构建节点实例规格（高配）"
  type        = string
  default     = "c5.2xlarge"  # AWS: 8C/16G
}

variable "build_node_max_count" {
  description = "构建节点最大数量"
  type        = number
  default     = 20
}

# ============================================================
# Jenkins 配置
# ============================================================
variable "jenkins_admin_password" {
  description = "Jenkins 管理员密码"
  type        = string
  sensitive   = true
}

variable "jenkins_storage_size" {
  description = "Jenkins 持久化存储大小"
  type        = string
  default     = "100Gi"
}

variable "storage_class_name" {
  description = "Kubernetes 存储类名称（根据集群存储方案调整，如 nfs-client、gp2、standard 等）"
  type        = string
  default     = "nfs-client"
}

# ============================================================
# Harbor 镜像仓库配置
# ============================================================
variable "harbor_url" {
  description = "Harbor 镜像仓库地址"
  type        = string
}

variable "harbor_username" {
  description = "Harbor 用户名"
  type        = string
  default     = "admin"
}

variable "harbor_password" {
  description = "Harbor 密码"
  type        = string
  sensitive   = true
}

# ============================================================
# GitLab 配置
# ============================================================
variable "gitlab_url" {
  description = "GitLab 地址（例：https://gitlab.your-company.com）"
  type        = string
}

variable "gitlab_token" {
  description = "GitLab Personal Access Token"
  type        = string
  sensitive   = true
}

# ============================================================
# SonarQube 配置
# ============================================================
variable "sonarqube_url" {
  description = "SonarQube 地址"
  type        = string
  default     = ""
}

variable "sonarqube_token" {
  description = "SonarQube 认证 Token"
  type        = string
  sensitive   = true
  default     = ""
}
