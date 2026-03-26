#!/usr/bin/env bash
# =============================================================
# 应用部署脚本
# 将应用部署到指定 Kubernetes 环境
# 用法: ./deploy.sh --app my-app --tag v1.2.3 --env prod
# =============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ============================================================
# 参数解析
# ============================================================
APP_NAME=""
IMAGE_TAG=""
ENVIRONMENT=""
HELM_CHART="./helm"
DRY_RUN=false
ROLLBACK=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --app)         APP_NAME="$2";    shift 2 ;;
        --tag)         IMAGE_TAG="$2";   shift 2 ;;
        --env)         ENVIRONMENT="$2"; shift 2 ;;
        --chart)       HELM_CHART="$2";  shift 2 ;;
        --dry-run)     DRY_RUN=true;     shift ;;
        --rollback)    ROLLBACK=true;    shift ;;
        -h|--help)
            echo "用法: $0 --app <应用名> --tag <镜像标签> --env <环境>"
            echo ""
            echo "选项:"
            echo "  --app APP       应用名称（必填）"
            echo "  --tag TAG       Docker 镜像标签（必填）"
            echo "  --env ENV       目标环境: dev | staging | prod（必填）"
            echo "  --chart PATH    Helm Chart 路径（默认: ./helm）"
            echo "  --dry-run       只执行 helm diff，不实际部署"
            echo "  --rollback      回滚到上一个版本"
            echo "  -h, --help      显示帮助"
            exit 0
            ;;
        *)
            log_error "未知参数: $1"
            exit 1
            ;;
    esac
done

# ============================================================
# 参数校验
# ============================================================
if [ -z "${APP_NAME}" ]; then
    log_error "缺少必填参数 --app"
    exit 1
fi

if [ -z "${ENVIRONMENT}" ]; then
    log_error "缺少必填参数 --env"
    exit 1
fi

if [ "${ROLLBACK}" = "false" ] && [ -z "${IMAGE_TAG}" ]; then
    log_error "缺少必填参数 --tag"
    exit 1
fi

# 环境到命名空间的映射
declare -A ENV_NAMESPACE_MAP=(
    ["dev"]="dev"
    ["staging"]="staging"
    ["prod"]="prod"
)

NAMESPACE="${ENV_NAMESPACE_MAP[${ENVIRONMENT}]:-${ENVIRONMENT}}"
VALUES_FILE="helm/values-${ENVIRONMENT}.yaml"

log_info "部署信息:"
log_info "  应用:   ${APP_NAME}"
log_info "  镜像:   ${IMAGE_TAG}"
log_info "  环境:   ${ENVIRONMENT}"
log_info "  命名空间: ${NAMESPACE}"

# ============================================================
# 回滚操作
# ============================================================
if [ "${ROLLBACK}" = "true" ]; then
    log_warn "执行回滚操作..."
    helm rollback "${APP_NAME}" -n "${NAMESPACE}" --wait
    log_success "${APP_NAME} 已回滚到上一个版本"

    # 验证回滚
    kubectl rollout status "deployment/${APP_NAME}" -n "${NAMESPACE}" --timeout=3m
    exit 0
fi

# ============================================================
# 部署前检查
# ============================================================
# 检查 Helm Chart 是否存在
if [ ! -d "${HELM_CHART}" ]; then
    log_error "Helm Chart 目录不存在: ${HELM_CHART}"
    exit 1
fi

# 检查 Values 文件
if [ ! -f "${VALUES_FILE}" ]; then
    log_warn "未找到环境专属 values 文件: ${VALUES_FILE}，使用默认配置"
    VALUES_FLAG=""
else
    VALUES_FLAG="--values ${VALUES_FILE}"
fi

# ============================================================
# 执行部署
# ============================================================
DRY_RUN_FLAG=""
if [ "${DRY_RUN}" = "true" ]; then
    log_warn "DRY RUN 模式，不实际部署"
    DRY_RUN_FLAG="--dry-run"
fi

helm upgrade --install "${APP_NAME}" "${HELM_CHART}" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set "image.tag=${IMAGE_TAG}" \
    ${VALUES_FLAG} \
    ${DRY_RUN_FLAG} \
    --wait \
    --timeout 5m \
    --atomic

if [ "${DRY_RUN}" = "true" ]; then
    log_success "Dry Run 完成，未实际部署"
    exit 0
fi

# ============================================================
# 部署验证
# ============================================================
log_info "验证部署状态..."
kubectl rollout status "deployment/${APP_NAME}" -n "${NAMESPACE}" --timeout=5m

# 获取 Pod 状态
READY_PODS=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
DESIRED_PODS=$(kubectl get deployment "${APP_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

log_success "部署完成！就绪 Pod: ${READY_PODS}/${DESIRED_PODS}"

# 显示当前部署信息
echo ""
echo "部署历史（最近3次）:"
helm history "${APP_NAME}" -n "${NAMESPACE}" --max 3

echo ""
log_success "${APP_NAME}:${IMAGE_TAG} 已成功部署到 ${ENVIRONMENT} 环境"
