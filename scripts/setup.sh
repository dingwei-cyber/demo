#!/usr/bin/env bash
# =============================================================
# CICD 平台初始化部署脚本
# 执行此脚本完成平台的完整部署
# =============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 加载颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ============================================================
# 解析命令行参数
# ============================================================
SKIP_INFRA=false
SKIP_HARBOR=false
ENVIRONMENT="dev"
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-infra)   SKIP_INFRA=true;   shift ;;
        --skip-harbor)  SKIP_HARBOR=true;  shift ;;
        --environment)  ENVIRONMENT="$2";  shift 2 ;;
        --force)        FORCE=true;        shift ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --skip-infra      跳过 Terraform 基础设施创建"
            echo "  --skip-harbor     跳过 Harbor 镜像仓库部署"
            echo "  --environment ENV 目标环境 (dev/staging/prod，默认: dev)"
            echo "  --force           强制重新部署（跳过存在性检查）"
            echo "  -h, --help        显示帮助信息"
            exit 0
            ;;
        *)
            log_error "未知参数: $1"
            exit 1
            ;;
    esac
done

# ============================================================
# 加载环境配置
# ============================================================
ENV_FILE="${SCRIPT_DIR}/env.local"
if [ ! -f "${ENV_FILE}" ]; then
    if [ -f "${SCRIPT_DIR}/env.example" ]; then
        log_warn "未找到 ${ENV_FILE}，请先复制并配置环境变量："
        log_warn "  cp scripts/env.example scripts/env.local"
        log_warn "  vim scripts/env.local"
        exit 1
    fi
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

# ============================================================
# 前置检查
# ============================================================
log_info "检查前置条件..."

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "未找到命令: $1，请先安装"
        exit 1
    fi
    log_success "$1 已安装: $(command -v "$1")"
}

check_command kubectl
check_command helm
check_command docker

if [ "${SKIP_INFRA}" = "false" ]; then
    check_command terraform
fi

# 检查 K8s 集群连接
log_info "验证 Kubernetes 集群连接..."
if ! kubectl cluster-info &> /dev/null; then
    log_error "无法连接到 Kubernetes 集群，请检查 kubeconfig"
    exit 1
fi
log_success "Kubernetes 集群连接正常"

# ============================================================
# Step 1: 基础设施创建（Terraform）
# ============================================================
if [ "${SKIP_INFRA}" = "false" ]; then
    log_info "Step 1/4: 创建/更新基础设施（Terraform）..."
    cd "${PROJECT_ROOT}/infrastructure/terraform"

    terraform init -upgrade
    terraform workspace select "${ENVIRONMENT}" 2>/dev/null || terraform workspace new "${ENVIRONMENT}"

    # 创建 tfvars 文件
    cat > "environments/${ENVIRONMENT}.tfvars" <<EOF
environment            = "${ENVIRONMENT}"
region                 = "${AWS_REGION:-us-east-1}"
cluster_name           = "${CLUSTER_NAME:-cicd-cluster}"
jenkins_admin_password = "${JENKINS_ADMIN_PASSWORD}"
harbor_url             = "${HARBOR_URL}"
harbor_username        = "${HARBOR_USERNAME}"
harbor_password        = "${HARBOR_PASSWORD}"
gitlab_url             = "${GITLAB_URL}"
gitlab_token           = "${GITLAB_TOKEN}"
sonarqube_url          = "${SONARQUBE_URL:-}"
sonarqube_token        = "${SONARQUBE_TOKEN:-}"
EOF

    terraform plan -var-file="environments/${ENVIRONMENT}.tfvars" -out=tfplan
    terraform apply tfplan
    log_success "基础设施创建完成"
    cd "${PROJECT_ROOT}"
else
    log_warn "Step 1/4: 跳过基础设施创建（--skip-infra）"
fi

# ============================================================
# Step 2: 创建 Jenkins 命名空间和基础资源
# ============================================================
log_info "Step 2/4: 配置 Kubernetes 资源..."

# 创建命名空间
kubectl get namespace jenkins &>/dev/null || kubectl create namespace jenkins
log_success "Jenkins 命名空间就绪"

# 创建 Jenkins 密钥
kubectl create secret generic jenkins-secrets \
    --from-literal=JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD}" \
    --from-literal=HARBOR_URL="${HARBOR_URL}" \
    --from-literal=HARBOR_USERNAME="${HARBOR_USERNAME}" \
    --from-literal=HARBOR_PASSWORD="${HARBOR_PASSWORD}" \
    --from-literal=GITLAB_URL="${GITLAB_URL}" \
    --from-literal=GITLAB_TOKEN="${GITLAB_TOKEN}" \
    --from-literal=SONARQUBE_URL="${SONARQUBE_URL:-}" \
    --from-literal=SONARQUBE_TOKEN="${SONARQUBE_TOKEN:-}" \
    -n jenkins \
    --dry-run=client -o yaml | kubectl apply -f -
log_success "Jenkins 密钥已配置"

# 应用 RBAC
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins
  namespace: jenkins
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: jenkins-agent-role
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/exec", "pods/log", "services", "endpoints",
                 "persistentvolumeclaims", "configmaps", "secrets", "events"]
    verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-agent-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: jenkins-agent-role
subjects:
  - kind: ServiceAccount
    name: jenkins
    namespace: jenkins
EOF
log_success "Jenkins RBAC 已配置"

# 创建 JCasC ConfigMap
kubectl create configmap jenkins-casc \
    --from-file="${PROJECT_ROOT}/jenkins/casc/jenkins.yaml" \
    -n jenkins \
    --dry-run=client -o yaml | kubectl apply -f -
log_success "Jenkins JCasC 配置已更新"

# ============================================================
# Step 3: 部署 Jenkins（Helm）
# ============================================================
log_info "Step 3/4: 部署 Jenkins..."

helm repo add jenkins https://charts.jenkins.io
helm repo update

helm upgrade --install jenkins jenkins/jenkins \
    --namespace jenkins \
    --values "${PROJECT_ROOT}/infrastructure/helm/jenkins/values.yaml" \
    --set controller.adminPassword="${JENKINS_ADMIN_PASSWORD}" \
    --wait \
    --timeout 10m

# 等待 Jenkins 就绪
log_info "等待 Jenkins 启动..."
kubectl rollout status deployment/jenkins -n jenkins --timeout=5m
log_success "Jenkins 已就绪"

# ============================================================
# Step 4: 构建并推送构建节点镜像
# ============================================================
log_info "Step 4/4: 构建 CI/CD 构建节点镜像..."

# 登录 Harbor
echo "${HARBOR_PASSWORD}" | docker login -u "${HARBOR_USERNAME}" --password-stdin "${HARBOR_URL}"

for lang in java nodejs python; do
    log_info "  构建 ${lang} 构建节点镜像..."
    docker build \
        -t "${HARBOR_URL}/build-agents/${lang}:latest" \
        -f "${PROJECT_ROOT}/docker/build-agents/${lang}/Dockerfile" \
        "${PROJECT_ROOT}/docker/build-agents/${lang}/"
    docker push "${HARBOR_URL}/build-agents/${lang}:latest"
    log_success "  ${lang} 构建节点镜像已推送"
done

# ============================================================
# 完成
# ============================================================
JENKINS_SVC_TYPE=$(kubectl get svc jenkins -n jenkins -o jsonpath='{.spec.type}' 2>/dev/null || echo "ClusterIP")
if [ "${JENKINS_SVC_TYPE}" = "LoadBalancer" ]; then
    JENKINS_EXT_IP=$(kubectl get svc jenkins -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    JENKINS_URL="http://${JENKINS_EXT_IP}:8080"
else
    JENKINS_URL="使用 kubectl port-forward: kubectl port-forward -n jenkins svc/jenkins 8080:8080"
fi

echo ""
echo "============================================================"
log_success "CICD 平台部署完成！"
echo "============================================================"
echo ""
echo "访问信息："
echo "  Jenkins URL:  ${JENKINS_URL}"
echo "  用户名:       admin"
echo "  密码:         (见环境变量 JENKINS_ADMIN_PASSWORD)"
echo ""
echo "下一步："
echo "  1. 在 GitLab 项目中配置 Webhook 指向 Jenkins"
echo "  2. 在 Jenkins 中运行 seed-job 生成所有 Pipeline Job"
echo "  3. 将 Jenkinsfile 添加到您的应用仓库"
echo "  详细说明请参考: docs/user-manual.md"
echo ""
