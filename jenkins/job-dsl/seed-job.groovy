/**
 * Jenkins Job DSL Seed Job
 *
 * 此脚本自动创建/更新所有 Jenkins Job
 * 只需在 Jenkins 中创建一个 "seed-job"，运行此脚本即可生成所有 Pipeline Job
 *
 * 添加新应用：在 applications 列表中添加新条目即可
 */

// ============================================================
// 应用配置列表
// ============================================================
def applications = [
    [
        name       : 'demo-java-app',
        description: 'Java 示例应用',
        repo       : "${GITLAB_URL}/team/demo-java-app.git",
        branch     : '*/main',
        language   : 'java',
        schedule   : 'H/5 * * * *',  // 定时轮询（也可用 Webhook）
    ],
    [
        name       : 'demo-node-app',
        description: 'Node.js 示例应用',
        repo       : "${GITLAB_URL}/team/demo-node-app.git",
        branch     : '*/main',
        language   : 'nodejs',
        schedule   : 'H/5 * * * *',
    ],
    [
        name       : 'demo-python-app',
        description: 'Python 示例应用',
        repo       : "${GITLAB_URL}/team/demo-python-app.git",
        branch     : '*/main',
        language   : 'python',
        schedule   : 'H/5 * * * *',
    ],
]

// ============================================================
// 生成 Pipeline Jobs
// ============================================================
applications.each { app ->
    multibranchPipelineJob(app.name) {
        description(app.description)
        displayName(app.name)

        branchSources {
            git {
                id("${app.name}-source")
                remote(app.repo)
                credentialsId('gitlab-ssh-key')
                includes(app.branch)
            }
        }

        orphanedItemStrategy {
            discardOldItems {
                numToKeep(10)
                daysToKeep(30)
            }
        }

        triggers {
            periodic(5)  // 每5分钟轮询一次
        }

        factory {
            workflowBranchProjectFactory {
                scriptPath('Jenkinsfile')
            }
        }
    }
}

// ============================================================
// 基础设施 Pipeline Jobs
// ============================================================
pipelineJob('infra-terraform-apply') {
    description('通过 Terraform 更新基础设施')
    displayName('Infra: Terraform Apply')

    parameters {
        stringParam('ENVIRONMENT', 'dev', '目标环境：dev | staging | prod')
        booleanParam('DRY_RUN', true, '是否仅 plan 而不 apply')
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url("${GITLAB_URL}/infra/cicd-platform.git")
                        credentials('gitlab-ssh-key')
                    }
                    branches('*/main')
                }
            }
            scriptPath('pipelines/Jenkinsfile.terraform')
        }
    }
}

pipelineJob('infra-update-jenkins') {
    description('更新 Jenkins JCasC 配置')
    displayName('Infra: Update Jenkins Config')

    triggers {
        scm('H/10 * * * *')
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url("${GITLAB_URL}/infra/cicd-platform.git")
                        credentials('gitlab-ssh-key')
                    }
                    branches('*/main')
                }
            }
            scriptPath('pipelines/Jenkinsfile.jenkins-config')
        }
    }
}

// ============================================================
// 视图配置
// ============================================================
listView('所有应用') {
    description('所有应用 CI/CD 流水线')
    columns {
        status()
        weather()
        name()
        lastSuccess()
        lastFailure()
        lastDuration()
        buildButton()
    }
    jobs {
        applications.each { app ->
            name(app.name)
        }
    }
}

listView('基础设施') {
    description('基础设施管理流水线')
    columns {
        status()
        weather()
        name()
        lastSuccess()
        lastFailure()
        lastDuration()
        buildButton()
    }
    jobs {
        name('infra-terraform-apply')
        name('infra-update-jenkins')
    }
}
