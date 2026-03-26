#!/usr/bin/env bash
# E2E 测试运行脚本（基于 Playwright）

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
RESULTS_DIR="${RESULTS_DIR:-e2e-results}"
RESULTS_FILE="${RESULTS_FILE:-e2e-test-results.xml}"

echo "============================================================"
echo "  E2E 测试开始"
echo "  目标 URL: ${BASE_URL}"
echo "============================================================"

cd "$(dirname "$0")"

if [ ! -f "package.json" ]; then
    echo "⚠️  E2E 测试目录中未找到 package.json，跳过 E2E 测试"
    exit 0
fi

# 安装依赖
npm ci

# 安装 Playwright 浏览器（无头模式）
npx playwright install --with-deps chromium

# 运行 E2E 测试
BASE_URL="${BASE_URL}" npx playwright test \
    --reporter=junit \
    --output="${RESULTS_DIR}" \
    || {
        echo "❌ E2E 测试失败"
        exit 1
    }

# 复制测试报告到根目录
if [ -f "${RESULTS_DIR}/junit.xml" ]; then
    cp "${RESULTS_DIR}/junit.xml" "../../${RESULTS_FILE}"
fi

echo "✅ E2E 测试通过"
