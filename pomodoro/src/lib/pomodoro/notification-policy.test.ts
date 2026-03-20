import { describe, expect, it } from "vitest";
import {
  canPromptForNotification,
  shouldShowBrowserNotification,
  type NotificationSupport,
} from "./notification-policy";

describe("NotificationPolicy", () => {
  it("never shows when user opted out", () => {
    const s: NotificationSupport = {
      kind: "supported",
      permission: "granted",
    };
    expect(shouldShowBrowserNotification(s, false)).toBe(false);
  });

  it("shows only when granted and opted in", () => {
    const granted: NotificationSupport = {
      kind: "supported",
      permission: "granted",
    };
    expect(shouldShowBrowserNotification(granted, true)).toBe(true);
    const denied: NotificationSupport = {
      kind: "supported",
      permission: "denied",
    };
    expect(shouldShowBrowserNotification(denied, true)).toBe(false);
  });

  it("unsupported never prompts", () => {
    const u: NotificationSupport = { kind: "unsupported" };
    expect(canPromptForNotification(u)).toBe(false);
    expect(shouldShowBrowserNotification(u, true)).toBe(false);
  });
});
