import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { TabCoordinator } from "./tab-coordinator";

describe("TabCoordinator", () => {
  const store: Record<string, string> = {};

  beforeEach(() => {
    vi.stubGlobal("localStorage", {
      getItem: (k: string) => (k in store ? store[k] : null),
      setItem: (k: string, v: string) => {
        store[k] = v;
      },
      removeItem: (k: string) => {
        delete store[k];
      },
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    for (const k of Object.keys(store)) delete store[k];
  });

  it("acquires when lease missing", () => {
    const c = new TabCoordinator("a", null);
    expect(c.tryAcquireLease(1000)).toBe(true);
    expect(c.isHolder()).toBe(true);
  });

  it("does not acquire when lease held by other tab", () => {
    store["pomodoro-lease-v1"] = JSON.stringify({
      ownerTabId: "other",
      expiresAt: 999_999,
    });
    const c = new TabCoordinator("b", null);
    expect(c.tryAcquireLease(1000)).toBe(false);
  });
});
