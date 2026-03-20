import { defineConfig, devices } from "@playwright/test";

/**
 * Local: `npm run test:e2e` starts `next dev` (reuse if something is already on the port).
 * CI (`CI=true`): either Playwright starts `next start`, OR you set `PLAYWRIGHT_TEST_BASE_URL`
 * and start the server yourself (avoids subprocess hangs in some CI/sandbox setups).
 */
const host = process.env.E2E_HOST ?? "127.0.0.1";
const port = process.env.E2E_PORT ?? "3000";
const externalBase = process.env.PLAYWRIGHT_TEST_BASE_URL?.replace(/\/$/, "");
const baseURL = externalBase ?? `http://${host}:${port}`;
const isCi = !!process.env.CI;
const useExternalServer = !!externalBase;

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: isCi,
  retries: isCi ? 2 : 0,
  workers: isCi ? 1 : undefined,
  timeout: 60_000,
  expect: {
    timeout: 20_000,
  },
  reporter: isCi
    ? process.env.GITHUB_ACTIONS
      ? [
          ["github"],
          ["list"],
          ["html", { open: "never", outputFolder: "playwright-report" }],
        ]
      : "line"
    : [["list"], ["html", { open: "never", outputFolder: "playwright-report" }]],
  use: {
    baseURL,
    trace: "on-first-retry",
    video: "retain-on-failure",
    screenshot: "only-on-failure",
    actionTimeout: 15_000,
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  // Never use stdout/stderr "pipe" without consuming — the buffer fills and Next blocks.
  webServer: useExternalServer
    ? undefined
    : isCi
      ? {
          command: `npm run start -- -H ${host} -p ${port}`,
          url: baseURL,
          reuseExistingServer: false,
          timeout: 120_000,
          stdout: "ignore",
          stderr: "ignore",
        }
      : {
          command: `npm run dev -- -H ${host} -p ${port}`,
          url: baseURL,
          reuseExistingServer: true,
          timeout: 120_000,
          stdout: "ignore",
          stderr: "ignore",
        },
});
