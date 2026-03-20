const CHANNEL_NAME = "pomodoro-tab";
const STORAGE_KEY = "pomodoro-lease-v1";

export type LeaseMessage =
  | { type: "claim"; tabId: string; ts: number }
  | { type: "release"; tabId: string }
  | { type: "ping"; tabId: string; ts: number };

export interface LeaseSnapshot {
  ownerTabId: string;
  expiresAt: number;
}

function readLease(): LeaseSnapshot | null {
  if (typeof localStorage === "undefined") return null;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as LeaseSnapshot;
    if (
      typeof parsed.ownerTabId === "string" &&
      typeof parsed.expiresAt === "number"
    ) {
      return parsed;
    }
  } catch {
    // corrupt lease — treat as empty
  }
  return null;
}

function writeLease(snapshot: LeaseSnapshot | null): void {
  if (typeof localStorage === "undefined") return;
  try {
    if (snapshot === null) {
      localStorage.removeItem(STORAGE_KEY);
    } else {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(snapshot));
    }
  } catch {
    // quota — ignore; coordinator still works via in-memory
  }
}

const LEASE_TTL_MS = 4000;

/**
 * Cross-tab lease: at most one tab should advance the timer.
 * Uses BroadcastChannel when available and localStorage for TTL lease record.
 */
export class TabCoordinator {
  private readonly tabId: string;
  private readonly channel: BroadcastChannel | null;
  private holder = false;

  constructor(tabId: string, channel: BroadcastChannel | null = null) {
    this.tabId = tabId;
    this.channel = channel;
  }

  static create(): TabCoordinator {
    const tabId =
      typeof crypto !== "undefined" && crypto.randomUUID
        ? crypto.randomUUID()
        : `tab-${Math.random().toString(36).slice(2)}`;
    const ch =
      typeof BroadcastChannel !== "undefined"
        ? new BroadcastChannel(CHANNEL_NAME)
        : null;
    return new TabCoordinator(tabId, ch);
  }

  getTabId(): string {
    return this.tabId;
  }

  isLeaseExpired(lease: LeaseSnapshot | null, now = Date.now()): boolean {
    if (!lease) return true;
    return lease.expiresAt <= now;
  }

  /** True if this tab may run the timer (holder or stale lease). */
  tryAcquireLease(now = Date.now()): boolean {
    const lease = readLease();
    if (this.isLeaseExpired(lease, now)) {
      this.holder = true;
      writeLease({ ownerTabId: this.tabId, expiresAt: now + LEASE_TTL_MS });
      this.post({ type: "claim", tabId: this.tabId, ts: now });
      return true;
    }
    if (lease?.ownerTabId === this.tabId) {
      this.holder = true;
      writeLease({ ownerTabId: this.tabId, expiresAt: now + LEASE_TTL_MS });
      return true;
    }
    this.holder = false;
    return false;
  }

  /** Renew while driving the timer. */
  heartbeat(now = Date.now()): void {
    if (!this.holder) return;
    writeLease({ ownerTabId: this.tabId, expiresAt: now + LEASE_TTL_MS });
    this.post({ type: "ping", tabId: this.tabId, ts: now });
  }

  release(): void {
    const lease = readLease();
    if (lease?.ownerTabId === this.tabId) {
      writeLease(null);
    }
    this.holder = false;
    this.post({ type: "release", tabId: this.tabId });
  }

  takeOver(now = Date.now()): void {
    this.holder = true;
    writeLease({ ownerTabId: this.tabId, expiresAt: now + LEASE_TTL_MS });
    this.post({ type: "claim", tabId: this.tabId, ts: now });
  }

  isHolder(): boolean {
    return this.holder;
  }

  onMessage(handler: (msg: LeaseMessage) => void): () => void {
    if (!this.channel) return () => {};
    const fn = (ev: MessageEvent) => {
      const data = ev.data as LeaseMessage;
      if (data && typeof data.type === "string") handler(data);
    };
    this.channel.addEventListener("message", fn);
    return () => this.channel?.removeEventListener("message", fn);
  }

  close(): void {
    this.channel?.close();
  }

  private post(msg: LeaseMessage): void {
    try {
      this.channel?.postMessage(msg);
    } catch {
      // ignore
    }
  }
}
