/**
 * Docker 构建并推送共享函数
 *
 * 使用示例：
 * dockerBuildPush(
 *     registry: 'harbor.your-company.com',
 *     image: 'team/my-app',
 *     tag: 'abc1234',
 *     dockerfile: 'Dockerfile',
 *     context: '.'
 * )
 */
def call(Map config = [:]) {
    ['registry', 'image', 'tag'].each { key ->
        if (!config.containsKey(key)) {
            error "dockerBuildPush: 缺少必填参数 '${key}'"
        }
    }

    config = [
        dockerfile: 'Dockerfile',
        context   : '.',
        buildArgs : [:],
        extraTags : []
    ] + config

    container('docker') {
        withCredentials([
            usernamePassword(
                credentialsId: 'harbor-credentials',
                usernameVariable: 'DOCKER_USER',
                passwordVariable: 'DOCKER_PASS'
            )
        ]) {
            script {
                def fullImage = "${config.registry}/${config.image}:${config.tag}"

                // 构建 --build-arg 参数
                def buildArgsStr = config.buildArgs.collect { k, v ->
                    "--build-arg ${k}=${v}"
                }.join(' ')

                sh """
                    echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin ${config.registry}
                    docker build \
                        -t ${fullImage} \
                        -f ${config.dockerfile} \
                        ${buildArgsStr} \
                        ${config.context}
                    docker push ${fullImage}
                """

                // 推送额外标签
                config.extraTags.each { extraTag ->
                    def taggedImage = "${config.registry}/${config.image}:${extraTag}"
                    sh """
                        docker tag ${fullImage} ${taggedImage}
                        docker push ${taggedImage}
                    """
                }

                echo "✅ 镜像已推送: ${fullImage}"
            }
        }
    }
}
