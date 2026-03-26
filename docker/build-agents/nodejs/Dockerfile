# Node.js 构建节点 Dockerfile
# 包含：Node.js 20 LTS, npm, yarn, pnpm, Docker CLI, kubectl, helm

FROM node:20-alpine

LABEL maintainer="DevOps Team <devops@your-company.com>"
LABEL description="Node.js CI/CD Build Agent"

ARG KUBECTL_VERSION=v1.28.4
ARG HELM_VERSION=v3.14.0

# 安装基础工具
RUN apk add --no-cache \
    bash \
    curl \
    wget \
    git \
    openssh-client \
    docker-cli \
    jq \
    python3 \
    make \
    g++ \
    ca-certificates \
    tzdata \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

# 安装 yarn 和 pnpm
RUN npm install -g yarn pnpm

# 安装 SonarQube Scanner
RUN npm install -g sonarqube-scanner

# 安装 kubectl
RUN wget -q "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# 安装 Helm
RUN wget -q "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    && tar -xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    && mv linux-amd64/helm /usr/local/bin/ \
    && rm -rf "helm-${HELM_VERSION}-linux-amd64.tar.gz" linux-amd64

# 配置 npm 私有仓库（替换为实际地址）
RUN npm config set registry ${NPM_REGISTRY:-https://registry.npmjs.org}

WORKDIR /workspace

# 验证安装
RUN node --version && npm --version && kubectl version --client && helm version

# 使用非 root 用户
RUN addgroup -S builder && adduser -S builder -G builder \
    && chown -R builder:builder /workspace

USER builder
