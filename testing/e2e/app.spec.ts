import { test, expect, Page } from '@playwright/test';

/**
 * E2E 测试示例
 * 验证应用核心页面和用户流程
 */

test.describe('应用核心功能 E2E 测试', () => {

    test.beforeEach(async ({ page }) => {
        // 导航到应用首页
        await page.goto(process.env.BASE_URL || 'http://localhost:8080');
    });

    test('首页正常加载', async ({ page }) => {
        // 检查页面标题
        await expect(page).toHaveTitle(/.*应用名称.*/);

        // 检查关键元素存在
        await expect(page.locator('h1')).toBeVisible();

        // 检查页面加载时间
        const loadTime = await page.evaluate(() => {
            return performance.timing.loadEventEnd - performance.timing.navigationStart;
        });
        expect(loadTime).toBeLessThan(3000);  // 页面加载应在 3 秒内完成
    });

    test('健康检查接口正常', async ({ page }) => {
        const response = await page.request.get('/health');
        expect(response.status()).toBe(200);

        const body = await response.json();
        expect(body.status).toBe('ok');
    });

    test('用户登录流程', async ({ page }) => {
        await page.goto('/login');

        // 填写登录表单
        await page.fill('[data-testid="username"]', 'testuser');
        await page.fill('[data-testid="password"]', 'testpassword');
        await page.click('[data-testid="login-button"]');

        // 验证登录成功，跳转到首页
        await page.waitForURL('/dashboard');
        await expect(page.locator('[data-testid="user-menu"]')).toBeVisible();
    });

});

test.describe('API 接口 E2E 验证', () => {

    test('GET /api/version 返回版本信息', async ({ request }) => {
        const response = await request.get('/api/version');
        expect(response.status()).toBe(200);

        const data = await response.json();
        expect(data).toHaveProperty('version');
        expect(data.version).toMatch(/^\d+\.\d+\.\d+$/);
    });

});
