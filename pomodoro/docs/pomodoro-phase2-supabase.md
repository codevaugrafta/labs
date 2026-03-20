# Phase 2: Supabase sync (specification)

This document satisfies the **phase2-supabase** planning item: schema, RLS, merge, and idempotency. **v1 does not ship this** — implement after guest mode is stable.

## Goals

- Optional sign-in; guest data merges on first login without duplicate `session_id` rows.
- Row Level Security: users only read/write their own rows.
- Account deletion and export (GDPR-shaped).

## Tables (sketch)

```sql
-- profiles: 1:1 with auth.users
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  timezone text default 'UTC',
  updated_at timestamptz default now()
);

create table public.pomodoro_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  session_id uuid not null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  phase_type text not null check (phase_type in ('work', 'shortBreak', 'longBreak')),
  duration_seconds int not null check (duration_seconds >= 0),
  task_title text not null default '',
  completed_work boolean not null default false,
  received_at timestamptz not null default now(),
  unique (user_id, session_id)
);

alter table public.pomodoro_sessions enable row level security;

create policy "own sessions select"
  on public.pomodoro_sessions for select
  using (auth.uid() = user_id);

create policy "own sessions insert"
  on public.pomodoro_sessions for insert
  with check (auth.uid() = user_id);

create policy "own sessions update"
  on public.pomodoro_sessions for update
  using (auth.uid() = user_id);

create policy "own sessions delete"
  on public.pomodoro_sessions for delete
  using (auth.uid() = user_id);
```

## Upload contract

- Client generates **`session_id`** (UUID) once per completed phase in v1; reuse the same ID when syncing.
- Server upserts on `(user_id, session_id)` conflict — **idempotent** retries.
- Reject if `ended_at < started_at` or `started_at` more than **30 days** before `received_at` (configurable).
- `received_at` is server default; used for ordering and abuse bounds, not for user-facing streaks (client streaks remain local-calendar based until account timezone is applied).

## Merge on first login

1. After auth session exists, read all local IndexedDB `pomodoro_sessions` rows.
2. Batch upsert to Supabase with the same `session_id` values.
3. On success, optionally clear local history or mark rows `synced` (product choice — document in PRD amendment).

## Clock skew

- Trust **duration_seconds** and **started_at/ended_at** from client for display; server validates sanity only.
- If server rejects a row, surface a non-blocking error and keep local copy.

## Account deletion

- `on delete cascade` from `auth.users` removes profile and sessions, or use soft-delete policy per product requirements.

## Next.js integration

- Server Actions or Route Handlers with Supabase service role **only** for admin tasks; normal path uses user JWT + RLS.
- Environment: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, server-only `SUPABASE_SERVICE_ROLE_KEY` if needed for migrations only.
