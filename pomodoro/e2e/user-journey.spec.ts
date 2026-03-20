import { expect, test } from "@playwright/test";

async function gotoReady(page: import("@playwright/test").Page) {
  await page.goto("/", { waitUntil: "domcontentloaded" });
  await expect(
    page.getByRole("heading", { name: "Pomodoro", level: 1 }),
  ).toBeVisible();
}

test.describe("Pomodoro user journey", () => {
  test("clicks every tab, task queue, skip records history, export enables", async ({
    page,
  }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });
    page.on("pageerror", (err) => consoleErrors.push(err.message));

    await gotoReady(page);

    await page.getByRole("tab", { name: "Today" }).click();
    await expect(
      page.locator('[data-slot="card-title"]').filter({ hasText: /^Today queue$/ }),
    ).toBeVisible();
    const taskInput = page.getByRole("textbox", {
      name: "New task for today queue",
    });
    await taskInput.fill("E2E task");
    await taskInput.press("Enter");
    await expect(page.getByRole("button", { name: "E2E task" })).toBeVisible();
    await page.getByRole("button", { name: "E2E task" }).click();

    await page.getByRole("tab", { name: "Timer" }).click();
    const taskField = page.getByPlaceholder("e.g. Draft PRD section");
    await expect(taskField).toHaveValue("E2E task");

    await page.getByRole("tab", { name: "History" }).click();
    await expect(
      page.getByRole("button", { name: "Export CSV" }),
    ).toBeDisabled();

    await page.getByRole("tab", { name: "Timer" }).click();
    await page.getByRole("button", { name: "Start" }).click();
    await expect(page.getByRole("button", { name: "Pause" })).toBeVisible();
    await expect(page.getByTestId("pomo-phase-ribbon")).toContainText(
      "Timer running",
    );

    await page.getByRole("button", { name: "Skip phase" }).click();
    await expect(page.getByTestId("pomo-phase-ribbon")).toContainText(
      "Short break",
    );
    await expect(page.getByTestId("pomo-phase-ribbon")).toContainText("Paused");

    await page.getByRole("tab", { name: "History" }).click();
    await expect(
      page.getByRole("button", { name: "Export CSV" }),
    ).toBeEnabled();
    await expect(page.getByText(/work/i).first()).toBeVisible();

    await page.getByRole("tab", { name: "Settings" }).click();
    await expect(
      page.locator('[data-slot="card-title"]').filter({ hasText: /^Durations$/ }),
    ).toBeVisible();
    await expect(
      page.getByRole("table", { name: "Timer keyboard shortcuts" }),
    ).toBeVisible();
    await expect(
      page.getByRole("cell", { name: "Space", exact: true }),
    ).toBeVisible();

    expect(
      consoleErrors,
      `console errors: ${consoleErrors.join("\n")}`,
    ).toEqual([]);
  });

  test("Space toggles run/pause when focus is on timer chrome", async ({
    page,
  }) => {
    await gotoReady(page);
    await page.getByTestId("pomo-phase-ribbon").click();
    await page.keyboard.press("Space");
    await expect(page.getByRole("button", { name: "Pause" })).toBeVisible();
    await page.keyboard.press("Space");
    await expect(page.getByRole("button", { name: "Resume" })).toBeVisible();
    await page.keyboard.press("Space");
    await expect(page.getByRole("button", { name: "Pause" })).toBeVisible();
  });

  test("Space does not toggle timer while typing in task field", async ({
    page,
  }) => {
    await gotoReady(page);
    const field = page.getByPlaceholder("e.g. Draft PRD section");
    await field.click();
    await field.fill("x");
    await page.keyboard.press("Space");
    await expect(field).toHaveValue("x ");
    await expect(page.getByRole("button", { name: "Start" })).toBeVisible();
  });
});
