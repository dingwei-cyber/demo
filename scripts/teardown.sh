#!/usr/bin/env bash
# =============================================================
# 环境清理脚本
# 销毁指定环境的所有资源（慎用！）
# =============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENVIRONMENT=""
DESTROY_INFRA=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --environment) ENVIRONMENT="$2"; shift 2 ;;
        --destroy-infra) DESTROY_INFRA=true; shift ;;
        --force)       FORCE=true;       shift ;;
        -h|--help)
            echo "用法: $0 --environment <环境>"
            echo ""
            echo "选项:"
            echo "  --environment ENV  目标环境: dev | staging | prod（必填）"
            echo "  --destroy-infra    同时销毁 Terraform 基础设施（危险！）"
            echo "  --force            跳过确认提示"
            echo ""
            echo "⚠️  警告：此操作不可逆！生产环境请谨慎操作。"
            exit 0
            ;;
        *)
            log_error "未知参数: $1"
            exit 1
            ;;
    esac
done

if [ -z "${ENVIRONMENT}" ]; then
    log_error "缺少必填参数 --environment"
    exit 1
fi

# 安全确认
if [ "${FORCE}" = "false" ]; then
    echo ""
    log_warn "⚠️  即将清理 ${ENVIRONMENT} 环境的所有资源！"
    if [ "${DESTROY_INFRA}" = "true" ]; then
        log_warn "⚠️  同时将销毁 Terraform 管理的基础设施！"
    fi
    echo ""
    read -rp "请输入环境名称确认操作 (${ENVIRONMENT}): " CONFIRM
    if [ "${CONFIRM}" != "${ENVIRONMENT}" ]; then
        log_error "确认失败，操作已取消"
        exit 1
    fi
fi

# ============================================================
# 清理 Helm Releases
# ============================================================
log_info "清理 ${ENVIRONMENT} 环境 Helm Releases..."

NAMESPACE="${ENVIRONMENT}"
RELEASES=$(helm list -n "${NAMESPACE}" -q 2>/dev/null || true)

if [ -n "${RELEASES}" ]; then
    while IFS= read -r release; do
        log_info "  卸载: ${release}"
        helm uninstall "${release}" -n "${NAMESPACE}" --wait 2>/dev/null || true
    done <<< "${RELEASES}"
else
    log_warn "命名空间 ${NAMESPACE} 中没有 Helm Releases"
fi

# ============================================================
# 清理命名空间
# ============================================================
if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
    log_info "删除命名空间: ${NAMESPACE}"
    kubectl delete namespace "${NAMESPACE}" --timeout=3m 2>/dev/null || true
fi

# ============================================================
# 清理 Jenkins（如果是 jenkins 环境）
# ============================================================
if [ "${ENVIRONMENT}" = "jenkins" ] || [ "${ENVIRONMENT}" = "dev" ]; then
    log_warn "是否同时清理 Jenkins？(y/N)"
    read -rp "输入 y 确认: " CLEAN_JENKINS
    if [ "${CLEAN_JENKINS}" = "y" ] || [ "${CLEAN_JENKINS}" = "Y" ]; then
        helm uninstall jenkins -n jenkins 2>/dev/null || true
        kubectl delete namespace jenkins --timeout=3m 2>/dev/null || true
        log_success "Jenkins 已清理"
    fi
fi

# ============================================================
# 销毁 Terraform 基础设施（可选）
# ============================================================
if [ "${DESTROY_INFRA}" = "true" ]; then
    log_warn "销毁 Terraform 基础设施..."

    ENV_FILE="${SCRIPT_DIR}/env.local"
    # shellcheck source=/dev/null
    [ -f "${ENV_FILE}" ] && source "${ENV_FILE}"

    cd "${PROJECT_ROOT}/infrastructure/terraform"
    terraform workspace select "${ENVIRONMENT}" 2>/dev/null || true
    terraform destroy \
        -var-file="environments/${ENVIRONMENT}.tfvars" \
        -auto-approve
    log_success "Terraform 基础设施已销毁"
fi

echo ""
log_success "环境 ${ENVIRONMENT} 清理完成"
