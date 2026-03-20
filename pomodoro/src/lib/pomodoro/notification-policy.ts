export type NotificationSupport =
  | { kind: "unsupported" }
  | { kind: "supported"; permission: NotificationPermission };

export function getNotificationSupport(): NotificationSupport {
  if (typeof window === "undefined" || typeof Notification === "undefined") {
    return { kind: "unsupported" };
  }
  return { kind: "supported", permission: Notification.permission };
}

/**
 * Browser notifications are optional; only true when user opted in and permission granted.
 */
export function shouldShowBrowserNotification(
  support: NotificationSupport,
  userOptIn: boolean,
): boolean {
  if (!userOptIn) return false;
  if (support.kind === "unsupported") return false;
  return support.permission === "granted";
}

export function canPromptForNotification(support: NotificationSupport): boolean {
  if (support.kind === "unsupported") return false;
  return support.permission === "default";
}
