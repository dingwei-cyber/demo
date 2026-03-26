# 用户使用说明手册

## CICD 自动化系统 — 用户操作指南

---

## 目录

1. [系统前置条件](#1-系统前置条件)
2. [快速开始](#2-快速开始)
3. [基础设施部署](#3-基础设施部署)
4. [Jenkins 配置与使用](#4-jenkins-配置与使用)
5. [GitLab 集成配置](#5-gitlab-集成配置)
6. [创建应用流水线](#6-创建应用流水线)
7. [自动化测试接入](#7-自动化测试接入)
8. [弹性构建节点管理](#8-弹性构建节点管理)
9. [制品与镜像管理](#9-制品与镜像管理)
10. [监控与告警](#10-监控与告警)
11. [常见问题排查](#11-常见问题排查)
12. [最佳实践](#12-最佳实践)

---

## 1. 系统前置条件

### 1.1 本地工具要求

在运维/管理机器上需安装以下工具：

| 工具 | 最低版本 | 说明 |
|------|---------|------|
| kubectl | 1.26+ | K8s 命令行工具 |
| helm | 3.12+ | Helm 包管理器 |
| terraform | 1.5+ | 基础设施即代码 |
| docker | 24+ | 容器构建工具 |
| git | 2.40+ | 版本控制 |

安装检查：

```bash
kubectl version --client
helm version
terraform version
docker version
git --version
```

### 1.2 基础设施要求

| 资源 | 最低配置 | 推荐配置 |
|------|---------|---------|
| Kubernetes 集群 | 3 Worker (4C/8G) | 5+ Worker (8C/16G) |
| Jenkins Controller | 2C/4G | 4C/8G |
| 持久化存储 | 50GB | 200GB |
| Harbor 镜像仓库 | 独立节点/共享K8s | 独立集群 |

### 1.3 网络要求

- Jenkins Controller 需要可访问 GitLab（Webhook 回调）
- K8s 集群 Worker 节点需要访问 Harbor 镜像仓库
- 构建节点 Pod 需要访问外网（拉取依赖）或配置私有代理

---

## 2. 快速开始

### 2.1 克隆系统仓库

```bash
git clone <your-gitlab-url>/infra/cicd-platform.git
cd cicd-platform
```

### 2.2 配置环境变量

复制并编辑配置文件：

```bash
cp scripts/env.example scripts/env.local
# 编辑以下必填项
vim scripts/env.local
```

需要填写的关键变量：

```bash
# Kubernetes
KUBECONFIG=/path/to/kubeconfig
K8S_NAMESPACE=jenkins

# Harbor 镜像仓库
HARBOR_URL=harbor.your-company.com
HARBOR_USERNAME=admin
HARBOR_PASSWORD=your_password

# GitLab
GITLAB_URL=https://gitlab.your-company.com
GITLAB_TOKEN=your_personal_access_token

# Jenkins
JENKINS_ADMIN_PASSWORD=your_secure_password
JENKINS_URL=http://jenkins.your-company.com
```

### 2.3 一键部署

```bash
# 给脚本添加执行权限
chmod +x scripts/*.sh

# 完整部署（基础设施 + Jenkins）
./scripts/setup.sh

# 仅部署 Jenkins（K8s 集群已存在时）
./scripts/setup.sh --skip-infra
```

部署完成后，访问 Jenkins：`http://<jenkins-url>`，默认管理员账号为配置文件中设置的账号。

---

## 3. 基础设施部署

### 3.1 使用 Terraform 创建 K8s 集群

```bash
cd infrastructure/terraform

# 初始化 Terraform
terraform init

# 查看将要创建的资源
terraform plan -var-file="environments/prod.tfvars"

# 创建资源（需确认）
terraform apply -var-file="environments/prod.tfvars"
```

创建 `environments/prod.tfvars` 文件：

```hcl
# 集群基本配置
cluster_name       = "cicd-cluster"
kubernetes_version = "1.28"
region             = "cn-hangzhou"

# 节点配置
node_count         = 3
node_instance_type = "ecs.c6.2xlarge"
node_disk_size     = 100

# 网络配置
vpc_cidr           = "10.0.0.0/16"
pod_cidr           = "172.16.0.0/16"
service_cidr       = "172.20.0.0/16"

# Jenkins 存储
jenkins_storage_size = "100Gi"
```

### 3.2 使用 Helm 部署 Jenkins

```bash
cd infrastructure/helm/jenkins

# 添加 Jenkins Helm 仓库
helm repo add jenkins https://charts.jenkins.io
helm repo update

# 部署 Jenkins
helm upgrade --install jenkins jenkins/jenkins \
  --namespace jenkins \
  --create-namespace \
  --values values.yaml \
  --wait

# 查看部署状态
kubectl get pods -n jenkins
```

### 3.3 验证部署

```bash
# 查看 Jenkins Pod 状态
kubectl get pods -n jenkins -w

# 查看 Jenkins 服务
kubectl get svc -n jenkins

# 获取 Jenkins 初始管理员密码（如果未使用 JCasC 配置）
kubectl exec -n jenkins \
  $(kubectl get pods -n jenkins -l app.kubernetes.io/name=jenkins -o jsonpath='{.items[0].metadata.name}') \
  -- cat /var/jenkins_home/secrets/initialAdminPassword
```

---

## 4. Jenkins 配置与使用

### 4.1 访问 Jenkins

部署完成后，通过以下方式访问：

- **Ingress URL**：`https://jenkins.your-company.com`（需配置 Ingress）
- **端口转发（临时）**：
  ```bash
  kubectl port-forward -n jenkins svc/jenkins 8080:8080
  # 访问 http://localhost:8080
  ```

### 4.2 Jenkins Configuration as Code（JCasC）

系统使用 JCasC 自动化配置 Jenkins，所有配置均在 `jenkins/casc/jenkins.yaml` 中管理。

修改配置后，有两种方式使配置生效：

**方式一：重新部署（推荐生产使用）**

```bash
# 更新 ConfigMap
kubectl create configmap jenkins-casc \
  --from-file=jenkins/casc/jenkins.yaml \
  -n jenkins --dry-run=client -o yaml | kubectl apply -f -

# 滚动重启 Jenkins
kubectl rollout restart deployment/jenkins -n jenkins
```

**方式二：在线 Reload（测试/调试用）**

```
Jenkins UI → Manage Jenkins → Configuration as Code → Reload existing configuration
```

### 4.3 查看流水线执行

1. 在 Jenkins 首页点击对应的 **Pipeline Job**
2. 点击具体的 **Build #** 查看执行详情
3. 点击 **Console Output** 查看实时日志
4. 使用 **Blue Ocean** 查看可视化流水线图

```
访问 Blue Ocean: http://<jenkins-url>/blue
```

### 4.4 手动触发流水线

```bash
# 使用 Jenkins CLI 触发
java -jar jenkins-cli.jar -s http://jenkins-url \
  -auth admin:your_token \
  build my-app-pipeline \
  -p BRANCH=main \
  -s -v

# 使用 API 触发
curl -X POST \
  "http://admin:your_token@jenkins-url/job/my-app-pipeline/buildWithParameters" \
  --data "BRANCH=main&ENVIRONMENT=dev"
```

---

## 5. GitLab 集成配置

### 5.1 配置 GitLab Webhook

在每个需要 CI/CD 的 GitLab 项目中：

1. 进入 **项目 → Settings → Webhooks**
2. 添加以下 Webhook：

```
URL: http://jenkins.your-company.com/gitlab-webhook/post
Secret Token: <jenkins-gitlab-webhook-token>
触发事件:
  ✅ Push events
  ✅ Merge request events
  ✅ Tag push events
```

3. 点击 **Test** 验证连接

### 5.2 配置 GitLab API Token

在 Jenkins 中添加 GitLab Token（用于状态回写）：

1. Jenkins → **Manage Jenkins** → **Manage Credentials**
2. 选择 Scope: **Global**
3. 添加类型 **GitLab API token**：
   - API token: `<your-gitlab-personal-access-token>`
   - ID: `gitlab-api-token`

### 5.3 在 GitLab 项目中启用 CI

在项目根目录添加 `Jenkinsfile`（从 `pipelines/Jenkinsfile` 复制并自定义），提交后自动触发。

---

## 6. 创建应用流水线

### 6.1 为新应用添加 Jenkinsfile

在应用仓库根目录创建 `Jenkinsfile`：

```groovy
@Library('cicd-shared-library') _

// 使用预置的 CI/CD 流水线
ciPipeline(
    appName: 'my-app',
    language: 'java',          // java | nodejs | python
    dockerRegistry: 'harbor.your-company.com',
    dockerRepo: 'my-team/my-app',
    testCommand: 'mvn test',
    buildCommand: 'mvn package -DskipTests',
    environments: [
        dev: [
            namespace: 'dev',
            values: 'helm/values-dev.yaml'
        ],
        staging: [
            namespace: 'staging',
            values: 'helm/values-staging.yaml'
        ],
        prod: [
            namespace: 'prod',
            values: 'helm/values-prod.yaml',
            requiresApproval: true    // 生产环境需人工审批
        ]
    ]
)
```

### 6.2 通过 Seed Job 批量创建 Jenkins Job

修改 `jenkins/job-dsl/seed-job.groovy`，添加新的应用：

```groovy
// 在 applications 列表中添加新应用
def applications = [
    [name: 'my-new-app', repo: 'https://gitlab.com/team/my-new-app.git', branch: 'main'],
    // ... 其他应用
]
```

然后运行 Seed Job 自动创建 Jenkins Job：

```
Jenkins → seed-job → Build Now
```

### 6.3 自定义流水线步骤

如果预置流水线不满足需求，可以自定义 Jenkinsfile：

```groovy
@Library('cicd-shared-library') _

pipeline {
    agent {
        kubernetes {
            yaml libraryResource('pod-templates/java-agent.yaml')
        }
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                container('maven') {
                    sh 'mvn clean package -DskipTests'
                }
            }
        }

        stage('Test') {
            parallel {
                stage('Unit Tests') {
                    steps {
                        container('maven') {
                            sh 'mvn test'
                            junit '**/target/surefire-reports/*.xml'
                        }
                    }
                }
                stage('Code Analysis') {
                    steps {
                        container('sonar') {
                            withSonarQubeEnv('sonarqube') {
                                sh 'mvn sonar:sonar'
                            }
                        }
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Build & Push Image') {
            steps {
                container('docker') {
                    script {
                        dockerBuildPush(
                            registry: 'harbor.your-company.com',
                            image: 'team/my-app',
                            tag: env.GIT_COMMIT[0..7]
                        )
                    }
                }
            }
        }

        stage('Deploy to Dev') {
            steps {
                helmDeploy(
                    releaseName: 'my-app',
                    chart: './helm/my-app',
                    namespace: 'dev',
                    valuesFile: 'helm/values-dev.yaml',
                    imageTag: env.GIT_COMMIT[0..7]
                )
            }
        }
    }

    post {
        always {
            // 发送通知（钉钉/企微/邮件）
            notifyBuild(channel: 'cicd-alerts')
        }
        success {
            archiveArtifacts artifacts: '**/target/*.jar', fingerprint: true
        }
    }
}
```

---

## 7. 自动化测试接入

### 7.1 单元测试接入

**Java (Maven)**

```bash
# 项目中已有 JUnit 测试，无需额外配置
# 在 Jenkinsfile 中加入：
sh 'mvn test'
junit '**/target/surefire-reports/*.xml'
```

**Python (pytest)**

```bash
# 安装测试依赖
pip install pytest pytest-cov

# 在 Jenkinsfile 中：
sh 'pytest tests/unit --junitxml=test-results.xml --cov=src --cov-report=xml'
junit 'test-results.xml'
```

**Node.js (Jest)**

```bash
# package.json 中配置
{
  "scripts": {
    "test": "jest --coverage --ci --reporters=default --reporters=jest-junit"
  }
}

# 在 Jenkinsfile 中：
sh 'npm test'
junit 'junit.xml'
```

### 7.2 集成测试接入

使用 Postman/Newman 进行 API 集成测试：

```bash
# 在 testing/integration/ 目录下放置 Postman Collection
# newman 运行示例（Jenkinsfile）
sh '''
  newman run testing/integration/api-tests.json \
    --environment testing/integration/env-dev.json \
    --reporters cli,junit \
    --reporter-junit-export integration-test-results.xml
'''
junit 'integration-test-results.xml'
```

### 7.3 E2E 测试接入

使用 Playwright：

```bash
# 在 testing/e2e/ 目录下配置 Playwright
cd testing/e2e
npm install

# playwright.config.ts 中配置目标环境 URL
export BASE_URL=https://dev.your-app.com

# 在 Jenkinsfile 中：
sh 'npx playwright test --reporter=junit'
junit 'test-results/junit.xml'
```

### 7.4 查看测试报告

- **JUnit 报告**：Jenkins Job → Test Results
- **Allure 报告**：Jenkins Job → Allure Report（需安装 Allure Plugin）
- **覆盖率报告**：Jenkins Job → Coverage Report（需安装 JaCoCo Plugin）

---

## 8. 弹性构建节点管理

### 8.1 查看当前构建节点

```bash
# 查看 Jenkins 命名空间中的 Agent Pod
kubectl get pods -n jenkins -l jenkins=agent

# 查看 Pod 资源占用
kubectl top pods -n jenkins
```

### 8.2 自定义构建节点资源

在 Jenkinsfile 中通过 YAML 模板自定义 Pod 规格：

```groovy
pipeline {
    agent {
        kubernetes {
            yaml '''
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: maven
    image: harbor.your-company.com/build-agents/java:17
    resources:
      requests:
        memory: "2Gi"
        cpu: "1000m"
      limits:
        memory: "4Gi"
        cpu: "2000m"
    volumeMounts:
    - name: maven-cache
      mountPath: /root/.m2
  volumes:
  - name: maven-cache
    persistentVolumeClaim:
      claimName: maven-cache-pvc
'''
        }
    }
    // ...
}
```

### 8.3 配置构建节点池

在 `jenkins/casc/jenkins.yaml` 中修改 Pod Template 配置：

```yaml
jenkins:
  clouds:
    - kubernetes:
        templates:
          - name: "java-agent"
            namespace: "jenkins"
            serviceAccount: "jenkins"
            containers:
              - name: "maven"
                image: "harbor.your-company.com/build-agents/java:17"
                resourceRequestCpu: "500m"
                resourceRequestMemory: "1Gi"
                resourceLimitCpu: "2000m"
                resourceLimitMemory: "4Gi"
```

### 8.4 构建节点自动扩缩容

Kubernetes 集群配置 **Cluster Autoscaler** 后，当构建任务队列增多时，K8s 会自动添加新的 Worker 节点；任务减少时自动缩容，降低成本。

验证 Autoscaler 状态：

```bash
kubectl get pods -n kube-system | grep cluster-autoscaler
kubectl logs -n kube-system deployment/cluster-autoscaler | tail -20
```

---

## 9. 制品与镜像管理

### 9.1 Harbor 镜像仓库

访问 Harbor：`https://harbor.your-company.com`

**镜像命名规范**：

```
harbor.your-company.com/<team>/<app>:<tag>

示例：
harbor.your-company.com/backend/user-service:1.2.3
harbor.your-company.com/frontend/web-app:abc1234
```

**标签策略**：

| 标签类型 | 格式 | 示例 | 说明 |
|---------|------|------|------|
| 提交标签 | `<git-short-sha>` | `abc1234` | CI 构建产物 |
| 版本标签 | `v<semver>` | `v1.2.3` | 正式发布版本 |
| 环境标签 | `<env>-latest` | `dev-latest` | 各环境最新版 |
| Latest | `latest` | `latest` | 生产最新版 |

### 9.2 制品清理策略

在 Harbor 中配置 Tag 保留策略（推荐）：

- 保留最新 10 个 tag
- 保留最近 30 天内推送的 tag
- 保留所有带版本号（v*）的 tag

---

## 10. 监控与告警

### 10.1 流水线监控面板

访问 Grafana 查看流水线监控：`https://grafana.your-company.com`

主要监控指标：

| 指标 | 含义 |
|------|------|
| Pipeline Success Rate | 流水线成功率 |
| Build Duration | 构建耗时分布 |
| Queue Wait Time | 任务等待时间 |
| Agent Pod Count | 活跃构建节点数 |
| Test Pass Rate | 测试通过率 |

### 10.2 配置通知

在 `jenkins/casc/jenkins.yaml` 中配置通知渠道：

**钉钉通知**：

```yaml
unclassified:
  dingTalk:
    robots:
      - id: "cicd-robot"
        name: "CICD告警"
        webhook: "https://oapi.dingtalk.com/robot/send?access_token=xxx"
        securityPolicyConfigs:
          - type: "SECRET"
            value: "your-secret"
```

**企业微信通知**：

```yaml
# 在 Jenkinsfile post 块中
post {
    failure {
        qyWechatNotification(
            webhookUrl: 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx',
            title: "构建失败",
            message: "项目：${env.JOB_NAME}\n分支：${env.BRANCH_NAME}\n构建：#${env.BUILD_NUMBER}"
        )
    }
}
```

### 10.3 查看构建节点资源使用

```bash
# 查看当前运行的 Agent Pod
kubectl get pods -n jenkins --field-selector=status.phase=Running

# 查看资源占用
kubectl top pods -n jenkins

# 查看集群节点资源
kubectl top nodes
```

---

## 11. 常见问题排查

### Q1: 构建节点 Pod 无法启动

```bash
# 检查 Pod 状态
kubectl describe pod <pod-name> -n jenkins

# 常见原因：
# 1. 镜像拉取失败 → 检查 Harbor 连接和认证
# 2. 资源不足 → 检查节点资源，考虑添加节点
# 3. 权限问题 → 检查 ServiceAccount 和 RBAC 配置
```

### Q2: GitLab Webhook 触发失败

```bash
# 检查 Jenkins 日志
kubectl logs -n jenkins <jenkins-pod-name> | grep -i webhook

# 常见原因：
# 1. 网络不通 → 检查防火墙规则
# 2. Token 不匹配 → 对比 Jenkins 和 GitLab 中的 Webhook Token
# 3. SSL 证书问题 → 在 GitLab 中关闭 SSL 验证（仅测试环境）
```

### Q3: 流水线卡在队列中

```bash
# 查看 Jenkins 构建队列
curl http://admin:token@jenkins-url/queue/api/json?pretty=true

# 检查 K8s 资源配额
kubectl describe resourcequota -n jenkins

# 手动清除等待中的 Pod
kubectl delete pods -n jenkins -l jenkins=agent --field-selector=status.phase=Pending
```

### Q4: Docker 镜像推送失败

```bash
# 检查 Harbor 认证
docker login harbor.your-company.com

# 检查 Jenkins 中 Harbor 凭证
# Jenkins → Manage Jenkins → Credentials → harbor-credentials

# 检查镜像仓库配额
# Harbor → Projects → your-project → Configuration → Storage Quota
```

### Q5: 重置 Jenkins 管理员密码

```bash
# 方式一：通过 JCasC 更新
# 修改 jenkins/casc/jenkins.yaml 中的密码配置后重启

# 方式二：通过 kubectl exec
kubectl exec -it -n jenkins <jenkins-pod> -- \
  /bin/bash -c "cd /var/jenkins_home && \
  java -jar /usr/share/jenkins/jenkins.war \
  --argumentsRealm.roles.user=admin \
  --argumentsRealm.passwd.admin=new_password"
```

---

## 12. 最佳实践

### 12.1 流水线设计原则

1. **快速失败**：单元测试放在最前面，尽早发现问题
2. **并行执行**：独立的测试/扫描任务并行运行，减少总耗时
3. **缓存利用**：Maven/npm 依赖缓存到 PVC，避免重复下载
4. **幂等性**：部署操作必须是幂等的（使用 `helm upgrade --install`）
5. **最小权限**：构建节点 ServiceAccount 仅授予必要权限

### 12.2 分支管理建议

```
main ←── release/* ←── develop ←── feature/*
                           ↑
                        hotfix/*
```

- 禁止直接 push 到 `main` 分支
- 所有变更通过 Merge Request 提交
- Merge Request 必须通过 CI 流水线才能合并
- `main` 分支的每次 commit 都是可发布的版本

### 12.3 密钥安全管理

```bash
# 不要在代码中明文存储任何密钥！

# 正确做法：将密钥存储在 Jenkins Credentials
# 在流水线中引用：
withCredentials([
    usernamePassword(
        credentialsId: 'harbor-credentials',
        usernameVariable: 'HARBOR_USER',
        passwordVariable: 'HARBOR_PASS'
    )
]) {
    sh 'docker login -u $HARBOR_USER -p $HARBOR_PASS harbor.your-company.com'
}
```

### 12.4 镜像构建最佳实践

```dockerfile
# 使用多阶段构建，减小最终镜像体积
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /app
COPY pom.xml .
# 先下载依赖（利用 Docker 缓存）
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn package -DskipTests

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
# 使用非 root 用户运行
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /app/target/*.jar app.jar
USER appuser
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### 12.5 资源成本优化

1. **设置 Pod 资源 Requests/Limits**，避免资源浪费
2. **配置 K8s 空闲节点自动缩容**，降低云费用
3. **定时清理旧的 Harbor 镜像**，节省存储成本
4. **构建缓存共享**：多个 Job 共享 Maven/npm 缓存 PVC
5. **非工作时间缩容**：利用 K8s CronJob 在非工作时间将节点缩减到最小

---

## 附录：常用命令速查

```bash
# 查看 Jenkins 日志
kubectl logs -f -n jenkins deployment/jenkins

# 重启 Jenkins
kubectl rollout restart deployment/jenkins -n jenkins

# 查看所有构建节点 Pod
kubectl get pods -n jenkins -l jenkins=agent

# 强制删除卡住的 Agent Pod
kubectl delete pod -n jenkins <pod-name> --force --grace-period=0

# 查看 Jenkins Helm 版本
helm history jenkins -n jenkins

# 回滚 Jenkins Helm
helm rollback jenkins 1 -n jenkins

# 更新 JCasC 配置
kubectl create configmap jenkins-casc \
  --from-file=jenkins/casc/jenkins.yaml \
  -n jenkins --dry-run=client -o yaml | kubectl apply -f -

# 查看 Terraform 状态
cd infrastructure/terraform && terraform show

# 销毁测试环境
./scripts/teardown.sh --environment dev
```
