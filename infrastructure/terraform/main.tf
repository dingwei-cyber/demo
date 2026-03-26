/**
 * Terraform 基础设施主配置
 * 管理 Kubernetes 集群和 Jenkins 相关云资源
 */

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # 根据您的云提供商取消注释对应的 provider
    # AWS EKS
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Azure AKS（可选）
    # azurerm = {
    #   source  = "hashicorp/azurerm"
    #   version = "~> 3.0"
    # }
    # Google GKE（可选）
    # google = {
    #   source  = "hashicorp/google"
    #   version = "~> 5.0"
    # }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  # Terraform 状态远程存储（推荐使用 S3/OSS/GCS）
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "cicd-platform/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

# ============================================================
# Cloud Provider 配置
# ============================================================
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "cicd-platform"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ============================================================
# Kubernetes 集群模块
# ============================================================
module "k8s_cluster" {
  source = "./modules/k8s-cluster"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  region             = var.region
  environment        = var.environment

  # 节点配置
  node_groups = {
    general = {
      instance_types = [var.node_instance_type]
      min_size       = var.node_min_count
      max_size       = var.node_max_count
      desired_size   = var.node_count
      disk_size      = var.node_disk_size
      labels = {
        role = "general"
      }
    }
    # 构建节点池（高配，用于 CI/CD 构建任务）
    build = {
      instance_types = [var.build_node_instance_type]
      min_size       = 0      # 弹性扩缩容，空闲时缩至0
      max_size       = var.build_node_max_count
      desired_size   = 0
      disk_size      = 50
      labels = {
        role = "build"
      }
      taints = [{
        key    = "dedicated"
        value  = "build"
        effect = "NO_SCHEDULE"
      }]
    }
  }

  # 网络配置
  vpc_cidr     = var.vpc_cidr
  pod_cidr     = var.pod_cidr
  service_cidr = var.service_cidr
}

# ============================================================
# 配置 Kubernetes & Helm Providers
# ============================================================
provider "kubernetes" {
  host                   = module.k8s_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.k8s_cluster.cluster_ca_certificate)
  token                  = module.k8s_cluster.cluster_token
}

provider "helm" {
  kubernetes {
    host                   = module.k8s_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.k8s_cluster.cluster_ca_certificate)
    token                  = module.k8s_cluster.cluster_token
  }
}

# ============================================================
# Jenkins 模块
# ============================================================
module "jenkins" {
  source = "./modules/jenkins"

  namespace              = "jenkins"
  jenkins_admin_password = var.jenkins_admin_password
  jenkins_storage_size   = var.jenkins_storage_size
  harbor_url             = var.harbor_url
  harbor_username        = var.harbor_username
  harbor_password        = var.harbor_password
  gitlab_url             = var.gitlab_url
  gitlab_token           = var.gitlab_token
  sonarqube_url          = var.sonarqube_url
  sonarqube_token        = var.sonarqube_token

  depends_on = [module.k8s_cluster]
}

# ============================================================
# 构建节点缓存 PVC（Maven/npm/pip 依赖缓存）
# ============================================================
resource "kubernetes_persistent_volume_claim" "maven_cache" {
  metadata {
    name      = "maven-cache-pvc"
    namespace = "jenkins"
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = var.storage_class_name
    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }
  depends_on = [module.jenkins]
}

resource "kubernetes_persistent_volume_claim" "npm_cache" {
  metadata {
    name      = "npm-cache-pvc"
    namespace = "jenkins"
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = var.storage_class_name
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
  depends_on = [module.jenkins]
}

resource "kubernetes_persistent_volume_claim" "pip_cache" {
  metadata {
    name      = "pip-cache-pvc"
    namespace = "jenkins"
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = var.storage_class_name
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
  depends_on = [module.jenkins]
}
