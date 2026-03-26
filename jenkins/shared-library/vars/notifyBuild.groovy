/**
 * 构建通知共享函数（支持钉钉、企业微信、邮件）
 *
 * 使用示例：
 * notifyBuild(channel: 'cicd-notifications')
 */
def call(Map config = [:]) {
    config = [
        channel      : 'cicd-notifications',
        onlyOnFailure: false,
    ] + config

    script {
        if (config.onlyOnFailure && currentBuild.result == 'SUCCESS') {
            return
        }

        def status    = currentBuild.result ?: 'SUCCESS'
        def emoji     = status == 'SUCCESS' ? '✅' : '❌'
        def duration  = currentBuild.durationString.replace(' and counting', '')
        def buildUrl  = env.BUILD_URL ?: ''
        def jobName   = env.JOB_NAME ?: ''
        def buildNum  = env.BUILD_NUMBER ?: ''
        def branch    = env.BRANCH_NAME ?: env.GIT_BRANCH ?: 'unknown'
        def commitSha = env.GIT_COMMIT?.take(8) ?: 'unknown'

        def message = """
${emoji} **构建${status == 'SUCCESS' ? '成功' : '失败'}**
- 项目: ${jobName}
- 分支: ${branch}
- 提交: ${commitSha}
- 构建: #${buildNum}
- 耗时: ${duration}
- 链接: ${buildUrl}
        """.trim()

        // 钉钉通知（如已安装 DingTalk 插件）
        try {
            dingtalk(
                robot: 'cicd-robot',
                type: 'TEXT',
                text: [message],
                at: []
            )
        } catch (Exception e) {
            echo "钉钉通知发送失败（插件未安装或配置错误）: ${e.message}"
        }

        // 企业微信通知（如已安装 WeCom 插件）
        try {
            qyWechatNotification(
                webhookUrl: env.WECHAT_WEBHOOK_URL ?: '',
                title: "${emoji} 构建${status == 'SUCCESS' ? '成功' : '失败'}",
                content: message
            )
        } catch (Exception e) {
            echo "企业微信通知发送失败（插件未安装或配置错误）: ${e.message}"
        }

        // 邮件通知（失败时）
        if (status != 'SUCCESS') {
            try {
                emailext(
                    subject: "${emoji} [CICD] ${jobName} #${buildNum} ${status}",
                    body: """<h2>${emoji} 构建${status}</h2>
                        <ul>
                            <li>项目: ${jobName}</li>
                            <li>分支: ${branch}</li>
                            <li>提交: ${commitSha}</li>
                            <li>构建: #${buildNum}</li>
                            <li>耗时: ${duration}</li>
                            <li><a href="${buildUrl}">查看详情</a></li>
                        </ul>""",
                    recipientProviders: [
                        [$class: 'CulpritsRecipientProvider'],
                        [$class: 'RequesterRecipientProvider']
                    ]
                )
            } catch (Exception e) {
                echo "邮件通知发送失败: ${e.message}"
            }
        }
    }
}
