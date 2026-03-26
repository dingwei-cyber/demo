# Java 构建节点 Dockerfile
# 包含：JDK 17, Maven 3.9, Docker CLI, kubectl, helm, sonar-scanner

FROM eclipse-temurin:17-jdk-alpine

LABEL maintainer="DevOps Team <devops@your-company.com>"
LABEL description="Java CI/CD Build Agent"

# 版本控制（便于升级）
ARG MAVEN_VERSION=3.9.6
ARG SONAR_SCANNER_VERSION=5.0.1.3006
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
    unzip \
    tar \
    ca-certificates \
    tzdata \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

# 安装 Maven
RUN wget -q "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
    && tar -xzf "apache-maven-${MAVEN_VERSION}-bin.tar.gz" -C /opt \
    && mv "/opt/apache-maven-${MAVEN_VERSION}" /opt/maven \
    && rm "apache-maven-${MAVEN_VERSION}-bin.tar.gz"

ENV MAVEN_HOME=/opt/maven
ENV PATH="${MAVEN_HOME}/bin:${PATH}"

# 安装 SonarQube Scanner
RUN wget -q "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip" \
    && unzip -q "sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip" -d /opt \
    && mv "/opt/sonar-scanner-${SONAR_SCANNER_VERSION}-linux" /opt/sonar-scanner \
    && rm "sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip"

ENV PATH="/opt/sonar-scanner/bin:${PATH}"

# 安装 kubectl
RUN wget -q "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# 安装 Helm
RUN wget -q "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    && tar -xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    && mv linux-amd64/helm /usr/local/bin/ \
    && rm -rf "helm-${HELM_VERSION}-linux-amd64.tar.gz" linux-amd64

# 预热 Maven 依赖缓存（可选）
RUN mkdir -p /root/.m2/repository

# 配置 Maven settings（使用私有仓库）
COPY settings.xml /root/.m2/settings.xml

# 设置工作目录
WORKDIR /workspace

# 验证安装
RUN java -version && mvn -version && kubectl version --client && helm version

# 使用非 root 用户（提高安全性）
RUN addgroup -S builder && adduser -S builder -G builder \
    && chown -R builder:builder /workspace /root/.m2

USER builder
