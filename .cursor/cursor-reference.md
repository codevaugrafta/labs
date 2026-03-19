# Cursor Technical Reference (March 2026)

Compiled from official documentation at cursor.com/docs and cursor.com/blog.

---

## Table of Contents

1. [Agent (Local)](#1-agent-local)
2. [Rules System](#2-rules-system)
3. [Skills](#3-skills)
4. [Hooks](#4-hooks)
5. [Plugins](#5-plugins)
6. [Cloud Agents](#6-cloud-agents)
7. [Automations](#7-automations)
8. [CLI](#8-cli)
9. [Multi-Agent Architecture](#9-multi-agent-architecture)
10. [Best Practices](#10-best-practices)

---

## 1. Agent (Local)

### Access
- Sidepane: `Cmd+I`
- Mode switching: `Shift+Tab` rotates through Agent / Plan / Ask modes
- Model switching: `Cmd+/` or dropdown

### Tools Available (No Call Limit)
| Tool | Approval Required | Notes |
|------|-------------------|-------|
| Semantic Search | No | Searches indexed codebase by meaning |
| File & Folder Search | No | Name, directory structure, keyword/pattern |
| File Reading | No | Supports .png, .jpg, .gif, .webp, .svg with vision models |
| File Editing | No (config files: Yes) | Writes to disk immediately |
| Shell Commands | Yes (by default) | Default terminal profile used |
| Web Search | No | Agent generates queries autonomously |
| Browser Control | -- | Screenshots, navigation, element interaction |
| Image Generation | -- | Text-to-image, saves to `assets/` folder |
| MCP Tool Calls | Yes | Both connection and individual calls need approval |
| Rules Retrieval | No | Dynamic loading based on type/description |

### Checkpoints
- Automatic snapshots before significant changes
- Preview files at any checkpoint
- Restore full codebase state
- Stored locally, separate from Git
- Access: chat timeline, "Restore Checkpoint" button, hover menu

### Message Queuing
- `Enter` = queue message (waits for agent to finish)
- `Cmd+Enter` = send immediately, bypassing queue (attaches to current tool results)
- Drag to reorder queued messages

### Security Defaults
- File reading & code search: no approval
- File modifications: auto-approved (except config files)
- Terminal commands: require approval
- MCP connections + individual tool calls: require approval
- `.cursorignore` blocks agent access to specified files
- Network: only GitHub, direct links, web search providers (no arbitrary requests)
- "Run Everything" mode: skips all safety checks (explicitly warned against)
- Workspace Trust: disabled by default; restricted mode disables AI features

### Context (Cursor 2.0+)
- Manual `@Web`, `@Git`, `@Linter Errors` eliminated -- agent self-gathers autonomously
- `@` mentions still work for: files, folders, code symbols, `@Docs`, `@Past Chats`, `@Branch`
- Drag-and-drop or `Cmd+V` for images
- Microphone icon for voice dictation

### Debug Mode
- Activation: mode picker dropdown or `Shift+Tab`
- 5-step process: explore -> instrument (add log statements to local debug server) -> reproduce (user follows steps) -> analyze logs -> fix & remove instrumentation
- Best for: reproducible bugs, race conditions, timing issues, perf degradation, memory leaks, regressions

### Plan Mode
- Activation: `Shift+Tab` or mode picker
- Process: clarifying questions -> codebase research -> implementation plan -> user review/edit -> build
- Storage: home directory by default; "Save to workspace" moves to workspace for team sharing
- Saved plans persist and are reusable
- Best for: complex multi-file features, unclear requirements, architectural decisions

---

## 2. Rules System

### Rule Types

| Type | Location | Scope | Format |
|------|----------|-------|--------|
| Project Rules | `.cursor/rules/` | Codebase (version-controlled) | `.md` or `.mdc` |
| User Rules | Cursor Settings | Global (Chat only) | Settings UI |
| Team Rules | Dashboard | Organization-wide (Team/Enterprise) | Dashboard UI |
| AGENTS.md | Project root or subdirectories | Codebase | Plain markdown |

### Precedence Order
**Team Rules > Project Rules > User Rules** (earlier sources override conflicts)

### `.mdc` Frontmatter Format
```yaml
---
description: "Rule purpose"
alwaysApply: false
globs: ["**/*.py"]
---
```

### Application Modes (type dropdown in `.mdc`)

| Mode | Behavior |
|------|----------|
| Always Apply | Every chat session |
| Apply Intelligently | Agent decides based on `description` field |
| Apply to Specific Files | Glob pattern matching via `globs` field |
| Apply Manually | Must `@`-mention in chat |

### Directory Structure
```
.cursor/rules/
  react-patterns.mdc
  api-guidelines.md
  frontend/
    components.md
```

### AGENTS.md
- Plain markdown, no frontmatter needed
- Place in project root or any subdirectory
- Subdirectory files inherit from parent; more specific overrides parent
- Supports a `## Cursor Cloud specific instructions` section for cloud-only setup

### Creation Methods
- `/create-rule` command in Agent chat
- Cursor Settings > Rules, Commands > + Add Rule

### Remote Rules
- Import from GitHub repos (public or private)
- Settings > Remote Rule option
- Auto-syncs updates

### File Referencing
- Use `@filename.ts` syntax to reference files without copying content

### Team Rule Enforcement
- Admins toggle "Enforce this rule" to prevent users from disabling

### Limitations
- User Rules do NOT apply to Inline Edit (`Cmd+K`)
- Rules do NOT affect Cursor Tab or other AI features
- Keep rules under 500 lines
- Split large rules into composable pieces

### Anti-Patterns
- Copying entire style guides (use a linter instead)
- Documenting every possible command
- Instructions for rarely-occurring edge cases
- Duplicating existing codebase documentation

---

## 3. Skills

### What They Are
Portable, version-controlled packages that teach agents domain-specific tasks. Open standard across agent platforms.

### File Structure
```
.agents/skills/
  skill-name/
    SKILL.md          # Required
    scripts/          # Optional: executable code
    references/       # Optional: additional docs (loaded on-demand)
    assets/           # Optional: templates, configs, images, data
```

### SKILL.md Frontmatter (YAML)
```yaml
---
name: skill-name               # Required: lowercase, matches parent folder
description: "What this does"   # Required: triggers agent relevance assessment
license: MIT                    # Optional
compatibility:                  # Optional
  - node >= 18
metadata:                       # Optional: arbitrary key-value
  category: testing
disable-model-invocation: false # Optional: true = explicit /slash only
---
```

### Discovery Directories (auto-scanned)
- `.agents/skills/` (project)
- `.cursor/skills/` (project)
- `~/.cursor/skills/` (user global)
- Legacy: `.claude/skills/`, `.codex/skills/`, and home-dir variants

### Activation
- **Automatic**: Agent evaluates context + description, invokes if relevant
- **Explicit**: Type `/skill-name` in Agent chat
- `disable-model-invocation: true` = slash command only, never auto-invoked

### Progressive Loading
Resources load on-demand to optimize token context usage.

### Migration Tool
`/migrate-to-skills` command (Cursor 2.4+) converts:
- Dynamic rules with `alwaysApply: false` (or undefined) without glob patterns -> standard skills
- User/workspace slash commands -> skills with `disable-model-invocation: true`
- Rules with `alwaysApply: true` or specific glob patterns are NOT migrated

### Management
Settings (`Cmd+Shift+J`) > Rules > "Agent Decides" section

---

## 4. Hooks

### What They Are
Spawned processes communicating via stdio JSON that observe, control, and extend the agent loop.

### Configuration Locations (Priority Order)
1. **Enterprise (system-wide)**:
   - macOS: `/Library/Application Support/Cursor/hooks.json`
   - Linux: `/etc/cursor/hooks.json`
   - Windows: `C:\ProgramData\Cursor\hooks.json`
2. **Team (cloud-distributed, enterprise only)**: Web dashboard
3. **Project**: `<project-root>/.cursor/hooks.json`
4. **User**: `~/.cursor/hooks.json`

Scripts run from their source directory (project hooks from project root, user hooks from `~/.cursor/`).

### Hook Types

**Command-Based (default)**
- Shell scripts: JSON via stdin, JSON via stdout
- Exit codes: `0` = success, `2` = block action, other = fail-open (default)
- Supports `timeout` (seconds) and `matcher` for filtering

**Prompt-Based**
- LLM-evaluated natural language conditions
- Returns `{ ok: boolean, reason?: string }`
- Supports `$ARGUMENTS` placeholder and optional `model` field override

### Agent Hook Events

| Event | Purpose |
|-------|---------|
| `sessionStart` / `sessionEnd` | Session lifecycle |
| `preToolUse` / `postToolUse` / `postToolUseFailure` | Generic tool lifecycle |
| `subagentStart` / `subagentStop` | Task tool (subagent) control |
| `beforeShellExecution` / `afterShellExecution` | Shell command control |
| `beforeMCPExecution` / `afterMCPExecution` | MCP tool control |
| `beforeReadFile` | File read access control |
| `afterFileEdit` | Post-edit processing |
| `beforeSubmitPrompt` | Pre-submission validation |
| `preCompact` | Context compaction (observational only, cannot block) |
| `stop` | Agent completion with auto-follow-up capability |
| `afterAgentResponse` / `afterAgentThought` | Response/reasoning tracking |

### Tab Hook Events (Inline Completions Only)
- `beforeTabFileRead`: File access control for Tab
- `afterTabFileEdit`: Tab edit post-processing

### Configuration Schema
```json
{
  "version": 1,
  "hooks": {
    "stop": [
      {
        "command": "bun run .cursor/hooks/grind.ts",
        "type": "command",
        "timeout": 30,
        "loop_limit": 5,
        "failClosed": false,
        "matcher": { "tool_type": "Shell" }
      }
    ]
  }
}
```

### Input Schema (All Hooks)
```json
{
  "conversation_id": "string",
  "generation_id": "string",
  "model": "string",
  "hook_event_name": "string",
  "cursor_version": "string",
  "workspace_roots": ["<path>"],
  "user_email": "string | null",
  "transcript_path": "string | null"
}
```

### Key Output Schemas

**preToolUse**:
```json
{
  "permission": "allow|deny",
  "user_message": "optional string",
  "agent_message": "optional string",
  "updated_input": "optional object"
}
```

**beforeShellExecution / beforeMCPExecution**:
```json
{
  "permission": "allow|deny|ask",
  "user_message": "optional",
  "agent_message": "optional"
}
```

**stop / subagentStop**:
```json
{
  "followup_message": "optional string"
}
```
Auto-submit with `loop_limit` (default 5, `null` for unlimited).

**sessionStart**:
```json
{
  "env": { "KEY": "VALUE" },
  "additional_context": "optional string"
}
```

### Matcher Filtering
- `preToolUse`/`postToolUse`/`postToolUseFailure`: `Shell`, `Read`, `Write`, `Grep`, `Delete`, `Task`, `MCP:<tool_name>`
- `subagentStart`/`subagentStop`: `generalPurpose`, `explore`, `shell`
- `beforeShellExecution`/`afterShellExecution`: command text regex
- `beforeReadFile`/`afterFileEdit`: tool type

### Environment Variables
- `CURSOR_PROJECT_DIR`, `CURSOR_VERSION`, `CURSOR_USER_EMAIL`
- `CURSOR_TRANSCRIPT_PATH`, `CURSOR_CODE_REMOTE` (`"true"` for remote)
- `CLAUDE_PROJECT_DIR` (alias)

### Critical Behaviors
- **Fail-open by default**: Crash/timeout/invalid JSON allows action through unless `failClosed: true`
- **Auto-reload**: Cursor watches `hooks.json` files, reloads on save
- **`preCompact` is read-only**: Cannot block or modify compaction
- Session-scoped env vars from `sessionStart` pass to all subsequent hooks

### Long-Running Agent Loop Pattern (via stop hook)
```typescript
// .cursor/hooks/grind.ts
// Input: JSON from stdin with conversation_id, status, loop_count
// Output: JSON with optional followup_message
const MAX_ITERATIONS = 5;
// Check .cursor/scratchpad.md for "DONE" signal
// If not done and loop_count < MAX_ITERATIONS, return followup_message
```

### Integration Partners
Snyk, Corridor, Semgrep, 1Password, Endor Labs, MintMCP, Oasis Security, Runlayer

---

## 5. Plugins

### What They Are
Distributable bundles packaging development tools. Components:
- Rules (.mdc files)
- Skills
- Agents (custom configurations)
- Commands
- MCP Servers
- Hooks

### Directory Structure
```
my-plugin/
  .cursor-plugin/
    plugin.json          # Manifest (required)
  rules/
    coding-standards.mdc
  skills/
    code-reviewer/
      SKILL.md
  .mcp.json
```

### Manifest (`plugin.json`)
```json
{
  "name": "my-plugin",
  "description": "Custom development tools",
  "version": "1.0.0",
  "author": { "name": "Your Name" }
}
```
Only `name` is required. Components auto-discovered from default directories.

### Distribution
- Submit to `cursor.com/marketplace/publish`
- Multi-plugin repos need `.cursor-plugin/marketplace.json`
- Every plugin manually reviewed before listing
- All marketplace plugins must be open source

### Team Marketplaces (Enterprise)
- Teams plan: up to 1 team marketplace
- Enterprise plan: unlimited
- Import GitHub repos via Dashboard > Settings > Plugins

### Installation
- Cursor Marketplace panel
- MCP deeplinks: `cursor://anysphere.cursor-deeplink/mcp/install?name=$NAME&config=$BASE64_ENCODED_CONFIG`
- Scope: project-level or user-level

### Limitations
- Cursor CLI does NOT support plugins yet
- Only MCP servers from plugins work in Cloud Agents

---

## 6. Cloud Agents

Formerly called "Background Agents."

### Access Methods
- `cursor.com/agents` (web)
- Cursor Desktop (Cloud dropdown)
- Slack: `@cursor` command
- GitHub: comment `@cursor` on PRs/issues
- Linear: `@cursor` command
- API
- Mobile PWA (iOS Safari share; Android Chrome menu)
- CLI: `-c` / `--cloud` flag

### How They Work
- Clone repo from GitHub/GitLab -> create branch -> work autonomously -> push changes / open PR
- Run in isolated VMs with full desktop environment (mouse, keyboard, browser control)
- Always in Max Mode (cannot disable)
- Charged at API pricing per model
- Run as many agents in parallel as you want; no local machine connection required

### Environment Configuration

**Agent-Driven Setup (Recommended)**
1. Navigate to `cursor.com/onboard`
2. Connect GitHub/GitLab, select repo
3. Provide env vars/secrets
4. Agent installs deps, verifies code
5. Save VM snapshot for reuse

**Manual Dockerfile**
- Create Dockerfile for system-level deps
- Do NOT use `COPY` for full project (Cursor manages workspace)
- Edit `.cursor/environment.json` directly

### `.cursor/environment.json`
Configuration resolution order:
1. `.cursor/environment.json` in repository
2. Personal environment configuration
3. Team environment configuration

### Update Commands
- Must be idempotent (e.g., `npm install`, `bazel build`, `pnpm install`)
- Cursor creates internal checkpoint snapshots if execution exceeds a few seconds

### Startup
- Executes `start` command, then configured `terminals`
- Docker: include `sudo service docker start` in start command
- Terminal processes run in shared `tmux` session

### Secrets Management
- Dashboard: `cursor.com/dashboard` > Secrets tab
- Encrypted at rest (KMS)
- Exposed as environment variables
- Shared across agents within workspaces or teams
- Optional redaction: prevents commits, masks values in tool results
- For monorepos: consolidate `.env` files into Secrets with unique prefixed names

### MCP Support
- HTTP transport (recommended): tool calls routed through backend, agent lacks direct credentials
- Stdio transport: server runs inside VM, agent has access to config and env vars
- OAuth support for per-user MCP servers
- NOT supported: SSE and `mcp-remote` transports
- MCP configs encrypted at rest

### CI/CD Integration
- Only GitHub Actions supported for automatic CI failure fixing
- Disable per-user or per-PR via `@cursor autofix`
- Currently Teams-only

### Security & Network

**Network Modes:**
1. "Allow all network access" -- unrestricted outbound
2. "Default + allowlist" -- approved domains + defaults
3. "Allowlist only" -- exclusively approved domains (Cursor services + SCM providers carved out)

**Egress IPs:** Published at `https://cursor.com/docs/ips.json` (CIDR, clustered by region)

**Signed Commits:**
- HSM-backed Ed25519 keys
- "Verified" badge on GitHub/GitLab
- Satisfies branch protection rules

**Privacy:**
- Code never used for training; retained only for running the agent
- Privacy mode locked at agent start (mid-run changes don't apply until completion)

**Auto-Execution Risk:**
- Agents auto-run terminal commands (no approval gate unlike local)
- Creates data exfiltration risk via prompt injection
- Internet access enabled by default

### Billing
- API pricing with mandatory spend limits
- Requires trial or paid plan with on-demand usage enabled

### Repository Support
- GitHub and GitLab (read-write privileges required for repo + submodules)
- Bitbucket: coming later

### Resource Limits
- Default VMs have limited memory and CPU
- Enterprise: contact support for increased limits
- Computer use NOT supported with Dockerfiles or snapshot-configured environments

---

## 7. Automations

### Triggers

| Trigger | Events |
|---------|--------|
| **Scheduled** | Recurring with preset or custom cron; may delay but won't run early |
| **GitHub** | Draft PR created, non-draft PR opened, draft marked ready, push to existing PR, PR merge, PR comment, push to branch (no PR), GitHub Check completion |
| **Slack** | Messages in public channels (top-level default; keyword/regex for threads), new public channel creation. Private channels NOT supported |
| **Webhook** | Private HTTP endpoint with API key auth |
| **Linear** | Issue creation, status change, cycle completion |
| **PagerDuty** | Incident creation, acknowledgment, resolution, any incident event |

### Available Tools

| Tool | Capability |
|------|-----------|
| Open Pull Request | Create branches, write code changes |
| Comment on PR | Top-level + inline; can approve/request changes if enabled |
| Request Reviewers | Identify domain experts via git + memory tools |
| Send to Slack | Dynamic or targeted channel messaging |
| Read Slack Channels | Read-only public channel access |
| MCP Server | External tools/data sources |
| Memories | Persistent notes across automation runs |

### Permission Scopes
- **Private**: individual user billed; admins can view/disable
- **Team Visible**: user billed; team members view-only
- **Team Owned**: billed to team's usage pool

---

## 8. CLI

### Installation
- macOS/Linux/WSL: `curl https://cursor.com/install -fsS | bash`
- Windows PowerShell: `irm 'https://cursor.com/install?win32=true' | iex`

### Core Commands
```bash
cursor agent                    # Start interactive session
cursor agent "prompt"           # Start with initial prompt
cursor agent ls                 # List previous chats
cursor agent resume             # Continue latest conversation
cursor agent --continue         # Resume previous session
cursor agent --resume="chat-id" # Open specific conversation
```

### Modes
| Mode | Flags | Shortcuts |
|------|-------|-----------|
| Agent | default | -- |
| Plan | `--plan`, `--mode=plan` | `Shift+Tab`, `/plan` |
| Ask | `--mode=ask` | `/ask` |

### Non-Interactive Flags
```bash
-p "prompt"              # Specify prompt text
--model "gpt-5.2"       # Select AI model
--output-format text     # Set output format
--sandbox <mode>         # enabled | disabled
```

### Cloud Agent from CLI
```bash
cursor agent -c              # Start cloud mode
cursor agent --cloud         # Same
```
`&` prefix mid-conversation sends task to Cloud Agent.

### In-Session Commands
- `/sandbox` -- interactive sandbox config menu
- `/max-mode [on|off]` -- toggle Max Mode

### Shell Mode
- Commands execute in login shell (`$SHELL`)
- 30-second timeout (not configurable)
- Large outputs auto-truncated
- No long-running processes, servers, or interactive prompts
- `cd` doesn't persist; use `cd dir && command`
- Expand truncated output: `Ctrl+O`
- Exit: `Escape` on empty input or `Ctrl+C`
- Commands checked against permissions and team settings

---

## 9. Multi-Agent Architecture (Scaling Blog)

### Architecture Evolution
1. **Flat structure (failed)**: Equal agents, shared coordination file, locking. Result: 20 agents -> 2-3 effective throughput, lock contention, brittleness.
2. **Optimistic concurrency (intermediate)**: Free reads, writes fail on stale state. Result: agents became risk-averse, no end-to-end ownership, prolonged churning.
3. **Planner-Worker (successful)**: Planners explore codebase, create tasks, spawn sub-planners recursively. Workers focus entirely on assigned tasks, push changes when done. Judge agent determines continuation each cycle.

### Scale Achieved
- Hundreds of concurrent agents on a single project
- 1 million lines of code across 1,000 files (~1 week runtime)
- Trillions of tokens deployed

### Reference Projects
| Project | Commits | Lines of Code |
|---------|---------|---------------|
| Java LSP | 7,400 | 550K |
| Windows 7 emulator | 14,600 | 1.2M |
| Excel implementation | 12,000 | 1.6M |
| Solid-to-React migration | 3+ weeks | +266K/-193K edits |

### Model Findings
- GPT-5.2: better at extended autonomous work, following instructions, maintaining focus, avoiding drift
- Opus 4.5: tends to stop earlier, takes shortcuts, yields control quickly
- GPT-5.2 outperformed GPT-5.1-Codex as planner (despite Codex's coding-specific training)
- Recommendation: use the best model per role, not one universal model

### Key Insights
- "Many improvements came from removing complexity rather than adding it"
- Integrator role abandoned (created bottlenecks)
- "Surprising amount of system behavior comes down to prompting"
- Periodic fresh starts needed to combat drift/tunnel vision
- Agents occasionally run far too long
- Right amount of structure is in the middle: too little = conflicts; too much = fragility

---

## 10. Best Practices

### Prompting
- Be specific: "Write test case for auth.ts covering logout edge case, using patterns in `__tests__/` and avoiding mocks" NOT "add tests for auth.ts"
- Focus on behavior not implementation: "Users must not see other users' data" NOT "Add RLS"
- One task per prompt
- Include business rules explicitly
- Reference specific files: "See auth.ts -- use that pattern"
- Use pseudo-code for complex logic before implementation

### Context Management
- Start fresh when: moving to different task, agent confused/repeating mistakes, logical unit completed
- Continue when: iterating on same feature, need earlier discussion context, debugging recent builds
- Use `@Past Chats` to reference previous work
- Use `@Branch` for branch-specific orientation
- Don't manually tag every file (agent searches on its own)
- Including irrelevant files confuses agent priorities

### Rules Best Practices
```markdown
# Commands
- `npm run build`: Build project
- `npm run typecheck`: Run typechecker
- `npm run test`: Run tests

# Code style
- Use ES modules (import/export), not CommonJS
- Destructure imports: `import { foo } from 'bar'`
- See `components/Button.tsx` for component structure

# Workflow
- Always typecheck after code changes
- API routes in `app/api/` following patterns
```

### Custom Commands
- Store in `.cursor/commands/` as markdown files
- Trigger with `/` prefix: `/pr`, `/fix-issue`, `/review`, `/update-deps`
- Autonomous multi-step workflows

### TDD Workflow
1. Ask agent to write tests (explicitly say "no implementation yet")
2. Confirm tests fail
3. Commit tests
4. Request implementation (explicitly say "no test modification")
5. Iterate until all tests pass
6. Commit implementation

### Cloud Agent Best Practices
- Configure environment before running (use `cursor.com/onboard`)
- Think of agent as "a smart, but low-context human developer"
- Document tips for running/debugging services in AGENTS.md
- Use MCP and custom tools to match human developer capabilities
- Iterate tools based on observing agent usage patterns
- Prevent agent distraction from noisy outputs (build logs, forgotten args)
- Ensure repos work well locally (if hard for humans, hard for agents)
- Whitelist all needed URLs if using egress controls

### Parallel Execution

**Worktrees:**
- Automatic git worktree creation per agent
- Each agent has isolated files and changes
- Select worktree option from agent dropdown
- Click "Apply" to merge changes back

**Multi-Model Comparison:**
- Select multiple models from dropdown simultaneously
- Compare results side-by-side
- Cursor suggests recommended solution

### Private Workers (Closed Beta)
- Run Cloud Agents on your own infrastructure
- Agent loop stays in Cursor's cloud; tool execution runs locally
- Only file chunks read by model leave your network
- Outbound HTTPS only (no inbound ports needed)
- Each agent gets dedicated worker
- Install: `curl -fsSL "https://www.cursor.com/install?channel=lab" | bash`
- Auth: CLI login (testing) or service account API key (production)
- Labels for matching agents to infrastructure: `--label env=production --label size=large`
- Idle release timeout: default 6 hours, configurable (600s for ephemeral, 31536000s for persistent)
- Kubernetes support: readiness probes (`/readyz` returns 200=ready, 503=busy) or API-driven scaling
- Management API: `GET /v0/private-workers`, `GET /v0/private-workers/summary`, `GET /v0/private-workers/{id}`
- Scale guidance: provision more when `inUse/totalConnected >= 0.9`
- Dashboard shows connected count, usage status, repos, labels, active agents

---

## Available Models (Referenced in Docs)

Claude family: 4.5 Haiku, 4.5 Sonnet, 4.6 Sonnet, Opus variants
Gemini family: 2.5 Flash, 3.1 Pro, 3 Flash/Pro
GPT family: 5 series with multiple variants
Others: Cursor Composer variants, Kimi K2.5, Grok Code

---

## Key File Paths Summary

| Path | Purpose |
|------|---------|
| `.cursor/rules/` | Project rules (`.md` or `.mdc`) |
| `.cursor/hooks.json` | Hook configuration |
| `.cursor/hooks/` | Hook scripts |
| `.cursor/commands/` | Custom slash commands (markdown) |
| `.cursor/plans/` | Saved plans from Plan Mode |
| `.cursor/environment.json` | Cloud agent environment config |
| `.cursor/scratchpad.md` | Agent loop completion signal file |
| `.cursor/skills/` | Project-level skills |
| `.agents/skills/` | Project-level skills (standard path) |
| `~/.cursor/skills/` | User-level global skills |
| `~/.cursor/hooks.json` | User-level hooks |
| `.cursorignore` | Block agent access to files |
| `AGENTS.md` | Agent instructions (root or subdirectories) |
| `.cursor-plugin/plugin.json` | Plugin manifest |
| `.mcp.json` | MCP server configuration |

---

## Beta / Experimental Features

| Feature | Status |
|---------|--------|
| Skills (`.SKILL.md`) | Stable (was nightly-only, now GA with Cursor 2.4+) |
| Private Workers | Closed Beta (contact Cursor for access) |
| `/migrate-to-skills` | Available in Cursor 2.4+ |
| Plugins / Marketplace | Available but all submissions manually reviewed |
| Cloud Agent CI autofix | Teams-only; other account types pending |
| Bitbucket support | Coming later |
| Computer use with Dockerfiles | Not currently supported |
