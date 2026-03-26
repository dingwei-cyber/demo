# CICD 自动化系统

> 基于 **Jenkins + GitLab + Kubernetes** 的企业级 CI/CD 自动化平台
> 支持弹性构建节点，一切皆代码（Everything as Code）

---

## 🚀 快速开始

```bash
# 1. 克隆仓库
git clone <your-repo-url>
cd demo

# 2. 配置环境变量
cp scripts/env.example scripts/env.local
vim scripts/env.local   # 填写实际配置

# 3. 一键部署
chmod +x scripts/*.sh
./scripts/setup.sh
```

## 📋 功能特性

| 特性 | 说明 |
|------|------|
| 🔧 Jenkins + JCasC | 配置即代码，Jenkins 全量配置通过 YAML 管理 |
| ⚡ 弹性构建节点 | Kubernetes Plugin 动态申请/释放 Pod，按需扩缩容 |
| 🔗 GitLab 集成 | Webhook 触发、MR 状态回写、Branch 策略支持 |
| 🧪 全链路测试 | 单元测试 → 集成测试 → E2E 测试 → 性能测试 |
| 🛡️ 安全扫描 | SonarQube SAST + Trivy 镜像扫描 |
| 📦 制品管理 | Harbor 私有镜像仓库 + 语义化版本管理 |
| 🏗️ IaC 基础设施 | Terraform + Helm 管理所有云资源 |
| 🔔 多渠道通知 | 钉钉 / 企业微信 / 邮件 |

## 📁 目录结构

```
demo/
├── docs/
│   ├── system-design.md      # 系统架构设计文档
│   └── user-manual.md        # 用户操作手册
├── infrastructure/
│   ├── terraform/            # Terraform IaC（云资源管理）
│   └── helm/jenkins/         # Jenkins Helm Chart 配置
├── jenkins/
│   ├── casc/jenkins.yaml     # Jenkins Configuration as Code
│   ├── shared-library/       # Jenkins 共享库（复用流水线逻辑）
│   └── job-dsl/              # Job DSL Seed Job
├── pipelines/
│   ├── Jenkinsfile           # 主流水线模板
│   ├── Jenkinsfile.release   # 发布流水线
│   └── .gitlab-ci.yml        # GitLab CI 配置
├── testing/
│   ├── unit/                 # 单元测试示例
│   ├── integration/          # 集成测试（Newman/Postman）
│   └── e2e/                  # E2E 测试（Playwright）
├── docker/
│   ├── jenkins-controller/   # Jenkins 主控镜像
│   └── build-agents/         # CI 构建节点镜像（Java/Node/Python）
└── scripts/
    ├── setup.sh              # 一键部署脚本
    ├── deploy.sh             # 应用部署脚本
    ├── teardown.sh           # 环境清理脚本
    └── env.example           # 环境变量模板
```

## 📖 文档

- [系统架构设计文档](docs/system-design.md)
- [用户操作手册](docs/user-manual.md)

## 🔄 流水线流程

```
代码提交 → 构建 → 单元测试 → 代码扫描 → 构建镜像 → 镜像扫描
    → 部署DEV → 集成测试 → 部署Staging → E2E测试 → [审批] → 部署生产
```

## 🏷️ 分支策略

| 分支 | 流水线 | 部署目标 |
|------|--------|---------|
| `feature/*` | CI | 无 |
| `develop` | CI + CD | Dev 环境 |
| `main` | CI + CD | Staging → Prod（需审批）|
| `release/*` | CI + CD | Staging → Prod（需审批）|
| `v*.*.*` (tag) | Release 流水线 | Staging → Prod |

## ⚙️ 技术栈

- **CI/CD**: Jenkins LTS + Kubernetes Plugin + Blue Ocean
- **代码管理**: GitLab
- **容器编排**: Kubernetes
- **基础设施**: Terraform + Helm
- **镜像仓库**: Harbor
- **代码质量**: SonarQube
- **安全扫描**: Trivy
- **测试框架**: JUnit / pytest / Jest / Playwright / Newman