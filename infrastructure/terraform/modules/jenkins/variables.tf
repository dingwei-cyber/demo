variable "namespace" {
  description = "Jenkins 命名空间"
  type        = string
  default     = "jenkins"
}

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

variable "jenkins_url" {
  description = "Jenkins 访问 URL"
  type        = string
  default     = ""
}

variable "harbor_url" {
  type      = string
  sensitive = false
}

variable "harbor_username" {
  type = string
}

variable "harbor_password" {
  type      = string
  sensitive = true
}

variable "gitlab_url" {
  type = string
}

variable "gitlab_token" {
  type      = string
  sensitive = true
}

variable "sonarqube_url" {
  type    = string
  default = ""
}

variable "sonarqube_token" {
  type      = string
  sensitive = true
  default   = ""
}
