# Jenkins Controller 自定义镜像
# 基于官方 Jenkins LTS 镜像，预安装插件，避免每次部署重新下载
#
# 构建命令（从仓库根目录执行，以便访问 jenkins/casc/jenkins.yaml）：
#   docker build -t jenkins-controller:latest -f docker/jenkins-controller/Dockerfile .

FROM jenkins/jenkins:2.440.3-lts-jdk17

# 切换 root 安装系统依赖
USER root

RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# 安装 Docker CLI（用于在 Controller 上执行 Docker 相关操作）
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
       https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# 安装 kubectl
ARG KUBECTL_VERSION=v1.28.4
RUN wget -q "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# 安装 Helm
ARG HELM_VERSION=v3.14.0
RUN wget -q "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    && tar -xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    && mv linux-amd64/helm /usr/local/bin/ \
    && rm -rf "helm-${HELM_VERSION}-linux-amd64.tar.gz" linux-amd64

# 安装 Jenkins 插件（通过 install-plugins.sh 预安装）
COPY docker/jenkins-controller/plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# 复制 JCasC 配置（构建上下文必须是仓库根目录）
COPY jenkins/casc/jenkins.yaml /usr/share/jenkins/ref/casc_configs/jenkins.yaml

# 设置 JCasC 配置目录
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/casc_configs

# 切换回 jenkins 用户
USER jenkins

# 设置时区
ENV TZ=Asia/Shanghai

EXPOSE 8080 50000
