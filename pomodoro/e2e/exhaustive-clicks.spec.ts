import { expect, test } from "@playwright/test";

async function gotoReady(page: import("@playwright/test").Page) {
  await page.goto("/", { waitUntil: "domcontentloaded" });
  await expect(
    page.getByRole("heading", { name: "Pomodoro", level: 1 }),
  ).toBeVisible();
}

function collectUiErrors(page: import("@playwright/test").Page, out: string[]) {
  page.on("console", (msg) => {
    if (msg.type() === "error") out.push(msg.text());
  });
  page.on("pageerror", (err) => out.push(err.message));
}

test.describe("Exhaustive click-through", () => {
  test("settings switches, theme, motion, reset dialog, timer, export CSV", async ({
    page,
  }) => {
    const errors: string[] = [];
    collectUiErrors(page, errors);

    await gotoReady(page);

    await page.getByRole("tab", { name: "Settings" }).click();
    await expect(
      page.locator('[data-slot="card-title"]').filter({ hasText: /^Durations$/ }),
    ).toBeVisible();

    const behaviorCard = page
      .locator('[data-slot="card"]')
      .filter({ hasText: "Auto-start next phase" });
    await behaviorCard.locator('[data-slot="switch"]').nth(0).click();
    await behaviorCard.locator('[data-slot="switch"]').nth(0).click();
    await behaviorCard.locator('[data-slot="switch"]').nth(1).click();
    await behaviorCard.locator('[data-slot="switch"]').nth(1).click();

    const notifCard = page
      .locator('[data-slot="card"]')
      .filter({ hasText: "Enable browser notifications" });
    await notifCard.locator('[data-slot="switch"]').first().click();
    await notifCard.locator('[data-slot="switch"]').first().click();

    await page.getByRole("button", { name: "light", exact: true }).click();
    await page.getByRole("button", { name: "dark", exact: true }).click();
    await page.getByRole("button", { name: "system", exact: true }).click();
    await page.getByRole("button", { name: "Reduce" }).click();
    await page
      .getByRole("button", { name: "System", exact: true })
      .click();

    const durationsCard = page
      .locator('[data-slot="card"]')
      .filter({ hasText: "Work (minutes)" });
    const workMin = durationsCard.locator('input[type="number"]').first();
    await workMin.fill("26");
    await workMin.fill("25");

    await page.getByRole("tab", { name: "Timer" }).click();
    await page.getByRole("button", { name: "Start" }).click();
    await page.getByRole("button", { name: "Pause" }).click();
    await page.getByRole("button", { name: "Reset" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Cancel" }).click();
    await expect(page.getByRole("button", { name: "Resume" })).toBeVisible();

    await page.getByRole("button", { name: "Reset" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Reset" }).click();
    await expect(page.getByRole("button", { name: "Start" })).toBeVisible();

    await page.getByRole("button", { name: "Start" }).click();
    await page.getByRole("button", { name: "Skip phase" }).click();
    await expect(page.getByTestId("pomo-phase-ribbon")).toContainText("Paused");

    await page.getByRole("tab", { name: "History" }).click();
    await expect(page.getByRole("button", { name: "Export CSV" })).toBeEnabled();

    const [download] = await Promise.all([
      page.waitForEvent("download"),
      page.getByRole("button", { name: "Export CSV" }).click(),
    ]);
    expect(download.suggestedFilename()).toMatch(/\.csv$/i);

    expect(errors, `console/page errors:\n${errors.join("\n")}`).toEqual([]);
  });
});
