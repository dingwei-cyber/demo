# Python 构建节点 Dockerfile
# 包含：Python 3.11, pip, Poetry, Docker CLI, kubectl, helm

FROM python:3.11-alpine

LABEL maintainer="DevOps Team <devops@your-company.com>"
LABEL description="Python CI/CD Build Agent"

ARG KUBECTL_VERSION=v1.28.4
ARG HELM_VERSION=v3.14.0
ARG POETRY_VERSION=1.8.2

# 安装基础工具
RUN apk add --no-cache \
    bash \
    curl \
    wget \
    git \
    openssh-client \
    docker-cli \
    jq \
    build-base \
    libffi-dev \
    openssl-dev \
    ca-certificates \
    tzdata \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

# 安装 Poetry（Python 包管理器）
RUN pip install --no-cache-dir "poetry==${POETRY_VERSION}"

# 安装常用测试工具
RUN pip install --no-cache-dir \
    pytest \
    pytest-cov \
    pytest-xdist \
    coverage \
    flake8 \
    black \
    mypy \
    bandit

# 安装 kubectl
RUN wget -q "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# 安装 Helm
RUN wget -q "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    && tar -xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    && mv linux-amd64/helm /usr/local/bin/ \
    && rm -rf "helm-${HELM_VERSION}-linux-amd64.tar.gz" linux-amd64

# 配置 pip 私有源（替换为实际地址）
RUN pip config set global.index-url ${PIP_INDEX_URL:-https://pypi.org/simple}

WORKDIR /workspace

# 验证安装
RUN python --version && pip --version && kubectl version --client && helm version

# 使用非 root 用户
RUN addgroup -S builder && adduser -S builder -G builder \
    && chown -R builder:builder /workspace

USER builder
