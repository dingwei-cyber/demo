/**
 * 主 CI/CD 流水线共享函数
 *
 * 使用示例：
 * @Library('cicd-shared-library') _
 * ciPipeline(
 *     appName: 'my-app',
 *     language: 'java',
 *     dockerRegistry: 'harbor.your-company.com',
 *     dockerRepo: 'team/my-app'
 * )
 */
def call(Map config = [:]) {
    // 必填参数校验
    ['appName', 'language', 'dockerRegistry', 'dockerRepo'].each { key ->
        if (!config.containsKey(key)) {
            error "ciPipeline: 缺少必填参数 '${key}'"
        }
    }

    // 默认参数
    config = [
        testCommand     : '',
        buildCommand    : '',
        sonarEnabled    : true,
        trivyEnabled    : true,
        environments    : [:],
        notifyChannel   : 'cicd-notifications',
        helmChart       : './helm',
        imageTagStrategy: 'gitsha',  // gitsha | semver | timestamp
    ] + config

    // 根据语言选择 Agent 标签
    def agentLabel = selectAgentLabel(config.language)

    pipeline {
        agent {
            kubernetes {
                label "${config.appName}-${agentLabel}-${env.BUILD_NUMBER}"
                yaml generatePodTemplate(config.language, config.dockerRegistry)
                defaultContainer agentContainerName(config.language)
            }
        }

        options {
            timeout(time: 60, unit: 'MINUTES')
            buildDiscarder(logRotator(numToKeepStr: '20', daysToKeepStr: '30'))
            disableConcurrentBuilds()
            timestamps()
            ansiColor('xterm')
        }

        environment {
            APP_NAME         = "${config.appName}"
            DOCKER_REGISTRY  = "${config.dockerRegistry}"
            DOCKER_REPO      = "${config.dockerRepo}"
            IMAGE_TAG        = generateImageTag(config.imageTagStrategy)
            FULL_IMAGE       = "${config.dockerRegistry}/${config.dockerRepo}:${IMAGE_TAG}"
            HARBOR_CREDS     = credentials('harbor-credentials')
        }

        stages {
            stage('初始化') {
                steps {
                    script {
                        // 输出构建信息
                        echo """
╔══════════════════════════════════════════════╗
║  应用名称: ${APP_NAME}
║  分支:     ${env.BRANCH_NAME ?: 'unknown'}
║  提交:     ${env.GIT_COMMIT?.take(8) ?: 'unknown'}
║  镜像标签: ${IMAGE_TAG}
╚══════════════════════════════════════════════╝
                        """
                        // 设置 GitLab 构建状态
                        updateGitlabCommitStatus name: 'jenkins-ci', state: 'running'
                    }
                }
            }

            stage('代码检出') {
                steps {
                    checkout scm
                    script {
                        env.GIT_COMMIT_MSG = sh(
                            script: 'git log -1 --pretty=%B',
                            returnStdout: true
                        ).trim()
                        env.GIT_AUTHOR = sh(
                            script: 'git log -1 --pretty=%an',
                            returnStdout: true
                        ).trim()
                    }
                }
            }

            stage('构建') {
                steps {
                    script {
                        def buildCmd = config.buildCommand ?: getDefaultBuildCommand(config.language)
                        sh buildCmd
                    }
                }
                post {
                    success {
                        script {
                            // 归档构建产物
                            archiveArtifacts artifacts: getArtifactPattern(config.language),
                                             allowEmptyArchive: true,
                                             fingerprint: true
                        }
                    }
                }
            }

            stage('单元测试') {
                steps {
                    script {
                        def testCmd = config.testCommand ?: getDefaultTestCommand(config.language)
                        sh testCmd
                    }
                }
                post {
                    always {
                        script {
                            publishTestResults(config.language)
                        }
                    }
                }
            }

            stage('代码质量扫描') {
                when {
                    expression { config.sonarEnabled }
                }
                steps {
                    container('sonar') {
                        withSonarQubeEnv('sonarqube') {
                            script {
                                sh getSonarCommand(config.language, config.appName)
                            }
                        }
                    }
                }
            }

            stage('质量门检查') {
                when {
                    expression { config.sonarEnabled }
                }
                steps {
                    timeout(time: 5, unit: 'MINUTES') {
                        waitForQualityGate abortPipeline: true
                    }
                }
            }

            stage('构建并推送镜像') {
                steps {
                    container('docker') {
                        script {
                            docker.withRegistry("https://${DOCKER_REGISTRY}", 'harbor-credentials') {
                                def image = docker.build(
                                    "${DOCKER_REPO}:${IMAGE_TAG}",
                                    "--file Dockerfile ."
                                )
                                image.push()
                                // 同时推送 latest 标签（非 feature 分支）
                                if (env.BRANCH_NAME in ['main', 'develop']) {
                                    image.push('latest')
                                }
                            }
                        }
                    }
                }
            }

            stage('镜像安全扫描') {
                when {
                    expression { config.trivyEnabled }
                }
                steps {
                    container('docker') {
                        script {
                            sh """
                                docker run --rm \
                                  -v /var/run/docker.sock:/var/run/docker.sock \
                                  aquasec/trivy image \
                                  --exit-code 1 \
                                  --severity HIGH,CRITICAL \
                                  --no-progress \
                                  ${FULL_IMAGE}
                            """
                        }
                    }
                }
            }

            stage('部署到开发环境') {
                when {
                    anyOf {
                        branch 'develop'
                        branch 'main'
                        branch pattern: 'release/.*', comparator: 'REGEXP'
                    }
                }
                steps {
                    script {
                        def devConfig = config.environments?.dev ?: [
                            namespace: 'dev',
                            values   : 'helm/values-dev.yaml'
                        ]
                        helmDeploy(
                            releaseName: config.appName,
                            chart      : config.helmChart,
                            namespace  : devConfig.namespace,
                            valuesFile : devConfig.values,
                            imageTag   : IMAGE_TAG,
                            registry   : DOCKER_REGISTRY
                        )
                    }
                }
            }

            stage('集成测试') {
                when {
                    anyOf {
                        branch 'develop'
                        branch 'main'
                        branch pattern: 'release/.*', comparator: 'REGEXP'
                    }
                }
                steps {
                    script {
                        sh 'if [ -f testing/integration/run-tests.sh ]; then bash testing/integration/run-tests.sh; fi'
                    }
                }
                post {
                    always {
                        junit allowEmptyResults: true, testResults: 'integration-test-results.xml'
                    }
                }
            }

            stage('部署到预发布环境') {
                when {
                    anyOf {
                        branch 'main'
                        branch pattern: 'release/.*', comparator: 'REGEXP'
                    }
                }
                steps {
                    script {
                        def stagingConfig = config.environments?.staging ?: [
                            namespace: 'staging',
                            values   : 'helm/values-staging.yaml'
                        ]
                        helmDeploy(
                            releaseName: config.appName,
                            chart      : config.helmChart,
                            namespace  : stagingConfig.namespace,
                            valuesFile : stagingConfig.values,
                            imageTag   : IMAGE_TAG,
                            registry   : DOCKER_REGISTRY
                        )
                    }
                }
            }

            stage('E2E 测试') {
                when {
                    anyOf {
                        branch 'main'
                        branch pattern: 'release/.*', comparator: 'REGEXP'
                    }
                }
                steps {
                    script {
                        sh 'if [ -f testing/e2e/run-tests.sh ]; then bash testing/e2e/run-tests.sh; fi'
                    }
                }
                post {
                    always {
                        junit allowEmptyResults: true, testResults: 'e2e-test-results.xml'
                    }
                }
            }

            stage('发布到生产环境') {
                when {
                    anyOf {
                        branch 'main'
                        branch pattern: 'release/.*', comparator: 'REGEXP'
                    }
                }
                steps {
                    script {
                        def prodConfig = config.environments?.prod ?: [
                            namespace       : 'prod',
                            values          : 'helm/values-prod.yaml',
                            requiresApproval: true
                        ]

                        if (prodConfig.requiresApproval) {
                            // 人工审批
                            timeout(time: 24, unit: 'HOURS') {
                                input message: """
审批请求：将 ${APP_NAME} 部署到生产环境

镜像: ${FULL_IMAGE}
提交: ${env.GIT_COMMIT?.take(8)}
作者: ${env.GIT_AUTHOR}

是否批准部署？
                                """, ok: '批准部署'
                            }
                        }

                        helmDeploy(
                            releaseName: config.appName,
                            chart      : config.helmChart,
                            namespace  : prodConfig.namespace,
                            valuesFile : prodConfig.values,
                            imageTag   : IMAGE_TAG,
                            registry   : DOCKER_REGISTRY
                        )
                    }
                }
            }
        }

        post {
            always {
                // 更新 GitLab 状态
                script {
                    def state = currentBuild.result == 'SUCCESS' ? 'success' : 'failed'
                    updateGitlabCommitStatus name: 'jenkins-ci', state: state
                }
                // 发送通知
                notifyBuild(channel: config.notifyChannel)
            }
            cleanup {
                cleanWs()
            }
        }
    }
}

// ====== 辅助函数 ======

def selectAgentLabel(String language) {
    def labels = [java: 'java', nodejs: 'nodejs', python: 'python']
    return labels.get(language, 'java')
}

def agentContainerName(String language) {
    def containers = [java: 'maven', nodejs: 'node', python: 'python']
    return containers.get(language, 'maven')
}

def generateImageTag(String strategy) {
    switch (strategy) {
        case 'semver':
            return env.TAG_NAME ?: env.GIT_COMMIT?.take(8) ?: 'latest'
        case 'timestamp':
            return new Date().format('yyyyMMdd-HHmmss')
        default: // gitsha
            return env.GIT_COMMIT?.take(8) ?: 'latest'
    }
}

def getDefaultBuildCommand(String language) {
    def commands = [
        java  : 'mvn clean package -DskipTests -B',
        nodejs: 'npm ci && npm run build',
        python: 'pip install -r requirements.txt && python setup.py build'
    ]
    return commands.get(language, 'mvn clean package -DskipTests -B')
}

def getDefaultTestCommand(String language) {
    def commands = [
        java  : 'mvn test -B',
        nodejs: 'npm test -- --ci --coverage',
        python: 'pytest tests/unit --junitxml=test-results.xml --cov=src --cov-report=xml'
    ]
    return commands.get(language, 'mvn test -B')
}

def getArtifactPattern(String language) {
    def patterns = [
        java  : '**/target/*.jar,**/target/*.war',
        nodejs: 'dist/**',
        python: 'dist/*.whl,dist/*.tar.gz'
    ]
    return patterns.get(language, '**/target/*.jar')
}

def getSonarCommand(String language, String appName) {
    def commands = [
        java  : "mvn sonar:sonar -Dsonar.projectKey=${appName}",
        nodejs: "npx sonar-scanner -Dsonar.projectKey=${appName}",
        python: "sonar-scanner -Dsonar.projectKey=${appName} -Dsonar.sources=src"
    ]
    return commands.get(language, "mvn sonar:sonar -Dsonar.projectKey=${appName}")
}

def publishTestResults(String language) {
    switch (language) {
        case 'java':
            junit allowEmptyResults: true, testResults: '**/target/surefire-reports/*.xml'
            jacoco execPattern: '**/target/jacoco.exec'
            break
        case 'nodejs':
            junit allowEmptyResults: true, testResults: 'junit.xml'
            break
        case 'python':
            junit allowEmptyResults: true, testResults: 'test-results.xml'
            cobertura coberturaReportFile: 'coverage.xml', failNoReports: false
            break
    }
}

def generatePodTemplate(String language, String registry) {
    return """
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: jenkins-agent
    language: ${language}
spec:
  serviceAccountName: jenkins
  containers:
    - name: jnlp
      image: jenkins/inbound-agent:latest-jdk17
      resources:
        requests:
          cpu: "200m"
          memory: "256Mi"
        limits:
          cpu: "500m"
          memory: "512Mi"
    ${getLanguageContainer(language, registry)}
    - name: docker
      image: docker:24-dind
      securityContext:
        privileged: true
      env:
        - name: DOCKER_TLS_CERTDIR
          value: ""
      resources:
        requests:
          cpu: "200m"
          memory: "256Mi"
        limits:
          cpu: "1000m"
          memory: "2Gi"
    - name: sonar
      image: sonarsource/sonar-scanner-cli:latest
      command: ["sleep"]
      args: ["infinity"]
      resources:
        requests:
          cpu: "200m"
          memory: "256Mi"
        limits:
          cpu: "500m"
          memory: "512Mi"
    - name: helm
      image: alpine/helm:3.14.0
      command: ["sleep"]
      args: ["infinity"]
      resources:
        requests:
          cpu: "100m"
          memory: "128Mi"
        limits:
          cpu: "500m"
          memory: "512Mi"
"""
}

def getLanguageContainer(String language, String registry) {
    switch (language) {
        case 'java':
            return """
    - name: maven
      image: ${registry}/build-agents/java:17
      command: ["sleep"]
      args: ["infinity"]
      resources:
        requests:
          cpu: "500m"
          memory: "1Gi"
        limits:
          cpu: "2000m"
          memory: "4Gi"
      volumeMounts:
        - name: maven-cache
          mountPath: /root/.m2
  volumes:
    - name: maven-cache
      persistentVolumeClaim:
        claimName: maven-cache-pvc
"""
        case 'nodejs':
            return """
    - name: node
      image: ${registry}/build-agents/nodejs:20
      command: ["sleep"]
      args: ["infinity"]
      resources:
        requests:
          cpu: "500m"
          memory: "1Gi"
        limits:
          cpu: "2000m"
          memory: "4Gi"
      volumeMounts:
        - name: npm-cache
          mountPath: /root/.npm
  volumes:
    - name: npm-cache
      persistentVolumeClaim:
        claimName: npm-cache-pvc
"""
        case 'python':
            return """
    - name: python
      image: ${registry}/build-agents/python:3.11
      command: ["sleep"]
      args: ["infinity"]
      resources:
        requests:
          cpu: "500m"
          memory: "1Gi"
        limits:
          cpu: "2000m"
          memory: "4Gi"
      volumeMounts:
        - name: pip-cache
          mountPath: /root/.cache/pip
  volumes:
    - name: pip-cache
      persistentVolumeClaim:
        claimName: pip-cache-pvc
"""
        default:
            return getLanguageContainer('java', registry)
    }
}
