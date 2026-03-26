# CICD 自动化系统方案文档

## 1. 系统概述

本系统基于 **Jenkins + GitLab + 自动化测试** 构建企业级 CI/CD 自动化流水线平台，核心特性：

- **弹性构建节点**：通过 Kubernetes 动态申请/释放构建资源，实现按需扩缩容
- **一切皆代码（Everything as Code）**：基础设施、流水线、配置均以代码形式管理
- **全链路自动化**：代码提交 → 构建 → 测试 → 制品发布 → 部署 → 验收 全流程自动化

---

## 2. 系统架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                          开发团队 (Developer)                         │
└─────────────────────┬───────────────────────────────────────────────┘
                      │ git push / merge request
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    GitLab (代码仓库 & Webhook)                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐ │
│  │  Source Repo│  │ Config Repo │  │   Infra Repo (IaC)          │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────────┘ │
└─────────────────────┬───────────────────────────────────────────────┘
                      │ Webhook 触发
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                Jenkins Controller (主控节点)                          │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Jenkins Configuration as Code (JCasC)                      │   │
│  │  Job DSL Seed Job │ Shared Library │ Pipeline Templates      │   │
│  └─────────────────────────────────────────────────────────────┘   │
└──────────────┬──────────────────────────────────────────────────────┘
               │ Kubernetes Plugin - 动态申请 Pod
               ▼
┌─────────────────────────────────────────────────────────────────────┐
│               Kubernetes 集群 (弹性构建节点池)                         │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────────┐  │
│  │Java Agent│ │Node Agent│ │ Python   │ │  Custom Agent        │  │
│  │  Pod     │ │  Pod     │ │ Agent Pod│ │  Pod                 │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────────────┘  │
└──────────────┬──────────────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      流水线执行阶段                                    │
│  ┌──────┐ ┌──────┐ ┌──────────┐ ┌──────────┐ ┌──────┐ ┌────────┐ │
│  │ 构建  │→│ 单测  │→│ 集成测试  │→│  制品发布  │→│ 部署  │→│ E2E测试 │ │
│  │Build │ │Unit  │ │Integration│ │  Publish │ │Deploy│ │  E2E   │ │
│  └──────┘ └──────┘ └──────────┘ └──────────┘ └──────┘ └────────┘ │
└─────────────────────────────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      制品与报告存储                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │
│  │  Harbor      │  │  SonarQube   │  │  Allure / JUnit Reports  │  │
│  │ (镜像仓库)    │  │ (代码质量)    │  │  (测试报告)               │  │
│  └──────────────┘  └──────────────┘  └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. 核心组件

### 3.1 GitLab — 代码托管与触发中心

| 功能 | 说明 |
|------|------|
| 代码仓库 | 应用代码、基础设施代码、流水线配置统一管理 |
| Merge Request | 触发 CI 流水线，合并前必须通过所有检查 |
| Webhook | 推送事件自动触发 Jenkins 流水线 |
| GitLab Runner | 可选作为轻量级 CI 执行器补充 |
| Container Registry | 存储 Docker 镜像（可选，也可用 Harbor 替代）|

### 3.2 Jenkins — 流水线编排引擎

| 功能 | 说明 |
|------|------|
| Jenkins Controller | 主控节点，负责调度与编排 |
| Kubernetes Plugin | 动态申请 Pod 作为构建节点，任务完成后自动回收 |
| JCasC | Jenkins Configuration as Code，配置即代码 |
| Shared Library | 复用流水线逻辑，避免代码重复 |
| Job DSL / Seed Job | 自动创建/更新 Jenkins Job |
| Blue Ocean | 可视化流水线 UI |

### 3.3 弹性构建节点 — Kubernetes Dynamic Agents

弹性节点基于 **Jenkins Kubernetes Plugin** 实现，核心流程：

1. Jenkins 收到触发信号
2. 根据 Jenkinsfile 中的 `agent { kubernetes { ... } }` 声明，向 K8s API 申请 Pod
3. Pod 启动后注册为 Jenkins Agent，执行构建任务
4. 任务完成后 Pod 自动删除，资源释放

支持的构建节点类型：

| 节点类型 | 镜像 | 适用场景 |
|---------|------|---------|
| Java Agent | `build-agent-java:latest` | Java/Maven/Gradle 构建 |
| Node.js Agent | `build-agent-nodejs:latest` | 前端/Node.js 构建 |
| Python Agent | `build-agent-python:latest` | Python 项目构建 |
| Custom Agent | 用户自定义 | 特殊构建需求 |

### 3.4 自动化测试框架

```
testing/
├── unit/         # 单元测试 (JUnit / pytest / Jest)
├── integration/  # 集成测试 (TestContainers / Postman/Newman)
└── e2e/          # 端到端测试 (Selenium / Playwright / Cypress)
```

| 测试层级 | 工具 | 触发时机 | 覆盖目标 |
|---------|------|---------|---------|
| 单元测试 | JUnit/pytest/Jest | 每次提交 | 函数/类逻辑 |
| 集成测试 | TestContainers/Newman | PR 合并前 | 服务间交互 |
| E2E 测试 | Playwright/Cypress | 部署到测试环境后 | 完整业务流程 |
| 性能测试 | k6/JMeter | 发布前 | 性能基准 |
| 代码扫描 | SonarQube | 每次构建 | 代码质量/安全 |

---

## 4. 基础设施即代码（IaC）

### 4.1 目录结构

```
infrastructure/
├── terraform/              # Terraform 管理云资源
│   ├── main.tf             # 主配置
│   ├── variables.tf        # 变量定义
│   ├── outputs.tf          # 输出值
│   └── modules/
│       ├── k8s-cluster/    # Kubernetes 集群（EKS/AKS/GKE/自建）
│       └── jenkins/        # Jenkins 相关资源
└── helm/                   # Helm Charts 管理 K8s 应用
    ├── jenkins/            # Jenkins Helm Chart 定制配置
    └── gitlab/             # GitLab Helm Chart 定制配置（可选）
```

### 4.2 技术栈选型

| 层次 | 工具 | 说明 |
|------|------|------|
| 云基础设施 | Terraform | IaC 管理 VPC、K8s 集群、存储等 |
| K8s 应用部署 | Helm | 打包、版本化 K8s 应用 |
| 容器运行时 | Docker / containerd | 构建和运行容器 |
| 制品存储 | Harbor | 私有容器镜像仓库 |
| 密钥管理 | Vault / K8s Secrets | 安全管理凭证 |
| 监控 | Prometheus + Grafana | 构建节点和流水线监控 |

---

## 5. 流水线设计

### 5.1 主流水线 (CI + CD)

```
代码提交
    │
    ▼
┌─────────────┐
│  Checkout   │  克隆代码
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Build     │  编译/打包
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Unit Tests  │  单元测试 + 覆盖率
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  SonarQube  │  代码质量扫描
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│ Build & Push    │  构建 Docker 镜像并推送到 Harbor
│ Docker Image    │
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│ Deploy to Dev   │  部署到开发环境
└──────┬──────────┘
       │
       ▼
┌──────────────────┐
│ Integration Tests│  集成测试
└──────┬───────────┘
       │
       ▼  (仅 main/release 分支)
┌─────────────────┐
│ Deploy to Staging│  部署到预发布环境
└──────┬──────────┘
       │
       ▼
┌─────────────┐
│  E2E Tests  │  端到端测试
└──────┬──────┘
       │
       ▼  (需要人工审批)
┌─────────────────┐
│Deploy to Prod   │  生产环境部署
└─────────────────┘
```

### 5.2 分支策略

| 分支 | 触发流水线 | 部署目标 |
|------|---------|---------|
| feature/* | CI (Build + Unit Test) | 无 |
| develop | CI + CD | 开发环境 |
| main | CI + CD | 预发布环境 → 生产环境（审批）|
| release/* | CI + CD | 预发布环境 → 生产环境（审批）|
| hotfix/* | CI + CD | 生产环境（快速通道）|

---

## 6. 安全设计

| 安全项 | 方案 |
|--------|------|
| 凭证管理 | Jenkins Credentials + HashiCorp Vault |
| 镜像安全扫描 | Trivy / Clair 集成到流水线 |
| 代码安全审计 | SonarQube SAST / OWASP Dependency Check |
| 网络隔离 | K8s NetworkPolicy 隔离构建命名空间 |
| RBAC | Jenkins Role-Based Access + K8s RBAC |
| 镜像签名 | cosign / Notary 对发布镜像签名 |

---

## 7. 高可用设计

| 组件 | 高可用方案 |
|------|---------|
| Jenkins Controller | K8s Deployment + PVC 持久化 + 备份 |
| GitLab | 主从复制 / GitLab HA 模式 |
| Harbor | 高可用部署 + 对象存储后端 |
| K8s 集群 | 多 Master 节点 + 多可用区 Worker |

---

## 8. 部署流程

### 快速启动（本地/测试环境）

```bash
# 1. 克隆此仓库
git clone <this-repo>
cd demo

# 2. 初始化基础设施（Terraform）
cd infrastructure/terraform
terraform init
terraform plan
terraform apply

# 3. 部署 Jenkins（Helm）
cd ../../
./scripts/setup.sh

# 4. 配置 GitLab Webhook
# 在 GitLab 项目中配置 Webhook 指向 Jenkins
# Payload URL: http://<jenkins-url>/gitlab-webhook/post

# 5. 创建 Seed Job 生成所有 Jenkins Job
# 在 Jenkins 中运行 seed-job
```

---

## 9. 目录结构总览

```
demo/
├── docs/
│   ├── system-design.md          # 本文档：系统架构方案
│   └── user-manual.md            # 用户使用手册
├── infrastructure/
│   ├── terraform/                # Terraform IaC
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── modules/
│   │       ├── k8s-cluster/      # K8s 集群模块
│   │       └── jenkins/          # Jenkins 资源模块
│   └── helm/
│       ├── jenkins/              # Jenkins Helm 定制配置
│       └── gitlab/               # GitLab Helm 定制配置
├── jenkins/
│   ├── casc/
│   │   └── jenkins.yaml          # JCasC 主配置
│   ├── shared-library/           # Jenkins 共享库
│   │   ├── vars/                 # 全局变量/函数
│   │   └── src/org/cicd/         # 辅助类
│   └── job-dsl/
│       └── seed-job.groovy       # Seed Job DSL
├── pipelines/
│   ├── Jenkinsfile               # 主流水线模板
│   ├── Jenkinsfile.release       # 发布流水线
│   └── .gitlab-ci.yml            # GitLab CI 配置模板
├── testing/
│   ├── unit/                     # 单元测试示例
│   ├── integration/              # 集成测试示例
│   └── e2e/                      # E2E 测试示例
├── docker/
│   ├── jenkins-controller/       # Jenkins 主控 Dockerfile
│   └── build-agents/             # 构建节点 Dockerfiles
│       ├── java/
│       ├── nodejs/
│       └── python/
├── scripts/
│   ├── setup.sh                  # 初始化部署脚本
│   ├── deploy.sh                 # 应用部署脚本
│   └── teardown.sh               # 环境清理脚本
└── README.md                     # 项目说明
```
