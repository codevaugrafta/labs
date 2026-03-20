import { expect, test } from "@playwright/test";

/** Client-only shell: first paint can be "Loading…" before `useIsClient` flips. */
async function gotoReady(page: import("@playwright/test").Page) {
  await page.goto("/", { waitUntil: "domcontentloaded" });
  await expect(
    page.getByRole("heading", { name: "Pomodoro", level: 1 }),
  ).toBeVisible();
}

test.describe("Pomodoro smoke", () => {
  test("home loads with core chrome", async ({ page }) => {
    await gotoReady(page);
    await expect(page.getByRole("tab", { name: "Timer" })).toBeVisible();
    await expect(page.getByRole("tab", { name: "Settings" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Start" })).toBeVisible();
    const ribbon = page.getByTestId("pomo-phase-ribbon");
    await expect(ribbon).toBeVisible();
    await expect(ribbon).toContainText("Focus");
    await expect(ribbon.getByText("Idle — start when ready")).toBeVisible();
  });

  test("settings tab shows durations", async ({ page }) => {
    await gotoReady(page);
    await page.getByRole("tab", { name: "Settings" }).click();
    await expect(
      page.locator('[data-slot="card-title"]').filter({ hasText: /^Durations$/ }),
    ).toBeVisible();
  });

  test("start switches primary control to pause", async ({ page }) => {
    await gotoReady(page);
    await page.getByRole("button", { name: "Start" }).click();
    await expect(page.getByRole("button", { name: "Pause" })).toBeVisible();
  });

  test("no uncaught exceptions on happy path", async ({ page }) => {
    const failures: string[] = [];
    page.on("pageerror", (err) => failures.push(err.message));
    await gotoReady(page);
    await page.getByRole("tab", { name: "History" }).click();
    await page.getByRole("tab", { name: "Timer" }).click();
    await page.getByRole("button", { name: "Start" }).click();
    await page.getByRole("button", { name: "Pause" }).click();
    expect(
      failures,
      `uncaught exceptions: ${failures.join("\n")}`,
    ).toEqual([]);
  });
});
