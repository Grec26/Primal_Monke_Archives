import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './browser-tests',
  use: { baseURL: 'http://127.0.0.1:4173', launchOptions: {
    ...(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}),
    args: ['--no-sandbox', '--enable-unsafe-swiftshader'],
  } },
  webServer: { command: 'npm run preview -- --port 4173', port: 4173, reuseExistingServer: false },
});
