import { describe, expect, it } from "vitest";
import { loadSessions } from "./local-store";

/**
 * Vitest uses Node (no IndexedDB). loadSessions must not throw — otherwise
 * PomodoroApp hydration's single try/catch drops settings/snapshot that loaded fine.
 */
describe("loadSessions", () => {
  it("returns empty array when IndexedDB is unavailable (Node)", async () => {
    await expect(loadSessions()).resolves.toEqual([]);
  });
});
