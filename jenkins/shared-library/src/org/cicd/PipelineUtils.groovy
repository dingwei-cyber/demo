package org.cicd

/**
 * 流水线工具类
 * 提供流水线执行中常用的辅助方法
 */
class PipelineUtils implements Serializable {

    private final def script

    PipelineUtils(def script) {
        this.script = script
    }

    /**
     * 解析 Git Tag 版本号（符合 SemVer）
     */
    static String parseSemver(String tagName) {
        def matcher = tagName =~ /^v?(\d+)\.(\d+)\.(\d+)(-.*)?$/
        if (matcher.matches()) {
            return "${matcher[0][1]}.${matcher[0][2]}.${matcher[0][3]}"
        }
        throw new IllegalArgumentException("无效的版本号格式: ${tagName}，期望格式: v1.2.3")
    }

    /**
     * 生成镜像标签
     */
    static String generateImageTag(String strategy, Map env) {
        switch (strategy) {
            case 'semver':
                def tag = env['TAG_NAME'] ?: env['GIT_COMMIT']
                return tag ? (tag.startsWith('v') ? tag.substring(1) : tag) : 'latest'
            case 'timestamp':
                return new Date().format('yyyyMMdd-HHmmss')
            case 'gitsha':
            default:
                def sha = env['GIT_COMMIT']
                return sha ? sha.take(8) : 'latest'
        }
    }

    /**
     * 检查当前分支是否为受保护分支
     */
    static boolean isProtectedBranch(String branchName) {
        def protectedBranches = ['main', 'master', 'develop', 'release']
        return protectedBranches.any { branchName?.startsWith(it) }
    }

    /**
     * 获取环境名称（从分支名推断）
     */
    static String getEnvironmentFromBranch(String branchName) {
        if (!branchName) return 'dev'
        if (branchName in ['main', 'master']) return 'prod'
        if (branchName == 'develop') return 'dev'
        if (branchName.startsWith('release/')) return 'staging'
        if (branchName.startsWith('hotfix/')) return 'prod'
        return 'dev'
    }

    /**
     * 格式化构建时长
     */
    static String formatDuration(long milliseconds) {
        def seconds = milliseconds / 1000
        def minutes = seconds / 60
        def hours   = minutes / 60

        if (hours >= 1) {
            return String.format('%d小时 %d分钟', (int) hours, (int) (minutes % 60))
        } else if (minutes >= 1) {
            return String.format('%d分钟 %d秒', (int) minutes, (int) (seconds % 60))
        } else {
            return String.format('%d秒', (int) seconds)
        }
    }

    /**
     * 安全执行 Shell 命令，失败不中断流水线
     */
    boolean safeShell(String command, boolean returnStatus = true) {
        def result = script.sh(script: command, returnStatus: true)
        if (result != 0) {
            script.echo "⚠️ 命令执行失败（exit code: ${result}）: ${command}"
            return false
        }
        return true
    }

    /**
     * 重试执行命令
     */
    def retryShell(String command, int maxRetries = 3, int sleepSeconds = 10) {
        int attempt = 0
        while (attempt < maxRetries) {
            attempt++
            try {
                script.sh command
                return
            } catch (Exception e) {
                if (attempt >= maxRetries) {
                    script.error "命令在 ${maxRetries} 次重试后仍失败: ${command}"
                }
                script.echo "第 ${attempt} 次尝试失败，${sleepSeconds} 秒后重试..."
                script.sleep(sleepSeconds)
            }
        }
    }
}
