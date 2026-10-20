import {defineConfig} from '@playwright/test';
// Runs on the locally installed Google Chrome; drop `channel` to use Playwright's bundled Chromium instead.
export default defineConfig({testDir:'./e2e',use:{baseURL:'http://127.0.0.1:5173',channel:'chrome',headless:true},webServer:{command:'npm run dev -- --port 5173',url:'http://127.0.0.1:5173',reuseExistingServer:true}});
