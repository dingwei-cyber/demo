# ============================================================
# K8s 集群模块 - 变量定义
# ============================================================

variable "cluster_name" {
  description = "集群名称"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes 版本"
  type        = string
}

variable "region" {
  description = "云服务区域"
  type        = string
}

variable "environment" {
  description = "环境名称"
  type        = string
}

variable "node_groups" {
  description = "节点组配置"
  type = map(object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
    disk_size      = number
    labels         = map(string)
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

variable "pod_cidr" {
  description = "Pod CIDR"
  type        = string
}

variable "service_cidr" {
  description = "Service CIDR"
  type        = string
}
