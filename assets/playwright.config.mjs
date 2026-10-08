import {defineConfig} from "@playwright/test"

export default defineConfig({
  testDir: "./browser-tests",
  outputDir: "../tmp/browser-test-results",
  workers: 1,
  timeout: 45000,
  use: {baseURL: process.env.BASE_URL || "http://localhost:8080", viewport: {width: 1440, height: 960}},
})
