#!/usr/bin/env python3
"""
单元测试示例 - Python 应用
演示如何在 CI 流水线中执行单元测试并生成报告
"""

import pytest
import os
import sys

# 添加源码目录到路径
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../src'))


class TestCicdUtils:
    """CI/CD 工具类单元测试示例"""

    def test_parse_semver_valid(self):
        """测试语义化版本号解析（正常情况）"""
        # 示例：测试版本号解析逻辑
        version = "v1.2.3"
        result = version.lstrip('v').split('.')
        assert result == ['1', '2', '3']
        assert len(result) == 3

    def test_parse_semver_invalid(self):
        """测试语义化版本号解析（异常情况）"""
        import re
        version = "invalid-version"
        pattern = r'^v?\d+\.\d+\.\d+$'
        assert not re.match(pattern, version)

    def test_environment_from_branch(self):
        """测试根据分支名推断环境"""
        branch_env_map = {
            'main': 'prod',
            'develop': 'dev',
            'release/1.0': 'staging',
            'feature/my-feature': 'dev',
            'hotfix/urgent-fix': 'prod',
        }
        for branch, expected_env in branch_env_map.items():
            result = get_environment_from_branch(branch)
            assert result == expected_env, f"分支 {branch} 期望环境 {expected_env}，实际: {result}"

    def test_generate_image_tag_gitsha(self):
        """测试 gitsha 镜像标签生成"""
        git_commit = "abc1234567890"
        tag = git_commit[:8]
        assert tag == "abc12345"
        assert len(tag) == 8

    def test_generate_image_tag_timestamp(self):
        """测试时间戳镜像标签生成"""
        from datetime import datetime
        tag = datetime.now().strftime('%Y%m%d-%H%M%S')
        import re
        assert re.match(r'^\d{8}-\d{6}$', tag)

    def test_environment_from_branch_edge_cases(self):
        """测试分支名推断环境的边界情况"""
        # 空字符串应返回 dev
        assert get_environment_from_branch('') == 'dev'
        # None 应返回 dev
        assert get_environment_from_branch(None) == 'dev'
        # master 分支与 main 分支一样返回 prod
        assert get_environment_from_branch('master') == 'prod'
        # release/ 前缀均返回 staging
        assert get_environment_from_branch('release/2.0.0') == 'staging'
        # 未知分支返回 dev
        assert get_environment_from_branch('experiment/new-idea') == 'dev'


def get_environment_from_branch(branch_name: str) -> str:
    """从分支名推断目标环境（测试辅助函数）"""
    if not branch_name:
        return 'dev'
    if branch_name in ('main', 'master'):
        return 'prod'
    if branch_name == 'develop':
        return 'dev'
    if branch_name.startswith('release/'):
        return 'staging'
    if branch_name.startswith('hotfix/'):
        return 'prod'
    return 'dev'


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--junitxml=test-results.xml',
                 '--cov=src', '--cov-report=xml', '--cov-report=term'])
