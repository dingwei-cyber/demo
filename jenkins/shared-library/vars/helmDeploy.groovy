/**
 * Helm 部署共享函数
 *
 * 使用示例：
 * helmDeploy(
 *     releaseName: 'my-app',
 *     chart: './helm/my-app',
 *     namespace: 'dev',
 *     valuesFile: 'helm/values-dev.yaml',
 *     imageTag: 'abc1234',
 *     registry: 'harbor.your-company.com'
 * )
 */
def call(Map config = [:]) {
    ['releaseName', 'chart', 'namespace', 'imageTag'].each { key ->
        if (!config.containsKey(key)) {
            error "helmDeploy: 缺少必填参数 '${key}'"
        }
    }

    config = [
        valuesFile      : '',
        extraArgs       : '',
        registry        : '',
        waitTimeout     : '5m',
        dryRun          : false,
    ] + config

    container('helm') {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
            script {
                def dryRunFlag = config.dryRun ? '--dry-run' : ''
                def valuesFlag = config.valuesFile ? "--values ${config.valuesFile}" : ''
                def registryFlag = config.registry ? "--set image.registry=${config.registry}" : ''

                sh """
                    helm upgrade --install ${config.releaseName} ${config.chart} \
                        --namespace ${config.namespace} \
                        --create-namespace \
                        --set image.tag=${config.imageTag} \
                        ${registryFlag} \
                        ${valuesFlag} \
                        ${config.extraArgs} \
                        ${dryRunFlag} \
                        --wait \
                        --timeout ${config.waitTimeout} \
                        --atomic
                """

                // 部署后验证
                if (!config.dryRun) {
                    sh """
                        kubectl rollout status deployment/${config.releaseName} \
                            -n ${config.namespace} \
                            --timeout=${config.waitTimeout}
                    """
                    echo "✅ ${config.releaseName} 已成功部署到 ${config.namespace} 环境，镜像版本: ${config.imageTag}"
                }
            }
        }
    }
}
