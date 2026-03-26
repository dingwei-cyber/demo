#!/usr/bin/env bash
# 集成测试运行脚本
# 使用 Newman (Postman CLI) 执行 API 集成测试

set -euo pipefail

# ============================================================
# 配置
# ============================================================
BASE_URL="${BASE_URL:-http://localhost:8080}"
ENV_FILE="${ENV_FILE:-testing/integration/environments/dev.json}"
COLLECTION_FILE="${COLLECTION_FILE:-testing/integration/api-tests.json}"
RESULTS_FILE="${RESULTS_FILE:-integration-test-results.xml}"
TIMEOUT="${TIMEOUT:-30000}"    # 请求超时（毫秒）
MAX_RETRIES="${MAX_RETRIES:-3}"

echo "============================================================"
echo "  集成测试开始"
echo "  目标环境: ${BASE_URL}"
echo "  测试集合: ${COLLECTION_FILE}"
echo "============================================================"

# ============================================================
# 等待服务就绪
# ============================================================
wait_for_service() {
    local url="$1"
    local max_wait="${2:-120}"
    local interval=5
    local elapsed=0

    echo "等待服务就绪: ${url}"
    while [ $elapsed -lt $max_wait ]; do
        if curl -sf --max-time 5 "${url}/health" > /dev/null 2>&1; then
            echo "✅ 服务已就绪 (${elapsed}s)"
            return 0
        fi
        echo "  服务尚未就绪，${interval}秒后重试... (${elapsed}/${max_wait}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    echo "❌ 等待服务超时（${max_wait}s）"
    return 1
}

# 等待目标服务就绪
wait_for_service "${BASE_URL}" 120

# ============================================================
# 运行 Newman 集成测试
# ============================================================
if ! command -v newman &> /dev/null; then
    echo "安装 Newman..."
    npm install -g newman newman-reporter-junit
fi

if [ ! -f "${COLLECTION_FILE}" ]; then
    echo "⚠️  集成测试集合文件不存在: ${COLLECTION_FILE}"
    echo "跳过集成测试"
    exit 0
fi

echo "运行集成测试..."
newman run "${COLLECTION_FILE}" \
    --environment "${ENV_FILE}" \
    --env-var "baseUrl=${BASE_URL}" \
    --reporters cli,junit \
    --reporter-junit-export "${RESULTS_FILE}" \
    --timeout-request "${TIMEOUT}" \
    --bail failure \
    || {
        echo "❌ 集成测试失败"
        exit 1
    }

echo "✅ 集成测试通过"
echo "测试报告: ${RESULTS_FILE}"
