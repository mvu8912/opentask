# AGENT.md (Bot/Agent Playbook)

This file is for bots/agents operating OpenTask.
It provides safe, repeatable usage patterns for all task operations to avoid misuse.

## 1) API contract at a glance

Base URL: `http://localhost:5000`

Task status lifecycle:
- New task => `new`
- Completed task => `done`

Primary identity rules:
- `app_id` scopes all data. Never mix task IDs across different `app_id` values.
- `task_uuid` is globally unique, but reads/updates still require the correct `app_id`.

## 2) Standard operation flow (recommended)

1. **Create** task (`POST /tasks`).
2. **Persist returned `task_uuid`** in your workflow context.
3. **Update** task details as work changes (`PUT /tasks/:id`).
4. **Get** latest state when you need authoritative details (`GET /tasks/:id`).
5. **List** periodically to coordinate backlog and done work (`GET /tasks`).
6. **Mark done** when truly complete (`POST /tasks/:id/done`).

## 3) Endpoint usage (agent-safe)

### Create task
`POST /tasks`

Required JSON body:
- `app_id`
- `title`
- `details` (markdown)

```bash
curl -sS -X POST http://localhost:5000/tasks \
  -H "Content-Type: application/json" \
  -d '{"app_id":"ops-bot","title":"Rotate API key","details":"## Steps\n- notify\n- rotate\n- verify"}'
```

Expected response:
```json
["<task-uuid>"]
```

Agent rule:
- Immediately store `<task-uuid>` in memory/context and logs.

---

### Update task (creates new version)
`PUT /tasks/:id`

Required JSON body:
- `app_id`
- `details`

```bash
curl -sS -X PUT http://localhost:5000/tasks/<task-uuid> \
  -H "Content-Type: application/json" \
  -d '{"app_id":"ops-bot","details":"## Progress\n- notified\n- rotating now"}'
```

Expected response:
```json
{"id":"<task-uuid>","message":"task Rotate API key has been updated, continue working until finish the whole task please."}
```

Agent rule:
- Use updates for meaningful progress changes only (avoid noisy micro-updates every few seconds).

---

### Get latest task
`GET /tasks/:id?app_id=...`

```bash
curl -sS "http://localhost:5000/tasks/<task-uuid>?app_id=ops-bot"
```

Agent rule:
- Treat this as the source of truth before finalizing or closing a task.

---

### List tasks
`GET /tasks?app_id=...`

Optional query params:
- `status=new|done`
- `from=YYYY-MM-DDTHH:MM:SS`
- `to=YYYY-MM-DDTHH:MM:SS`
- `search=keyword`

Examples:

```bash
curl -sS "http://localhost:5000/tasks?app_id=ops-bot"
```

```bash
curl -sS "http://localhost:5000/tasks?app_id=ops-bot&status=new"
```

```bash
curl -sS "http://localhost:5000/tasks?app_id=ops-bot&search=rotate"
```

Agent rules:
- Use `status=new` when selecting next executable work.
- Use `search` for contextual recall; do not assume search returns only title matches.
- Date filters compare timestamp strings; use ISO-like format exactly.

---

### Mark task as done
`POST /tasks/:id/done`

Required JSON body:
- `app_id`

```bash
curl -sS -X POST http://localhost:5000/tasks/<task-uuid>/done \
  -H "Content-Type: application/json" \
  -d '{"app_id":"ops-bot"}'
```

Possible response with next task:
```json
{"this-task":"<uuid>","message":"task Rotate API key is completed, move on to the next task <next-uuid>","next-task":"<next-uuid>"}
```

Possible response if no next task:
```json
{"this-task":"<uuid>","message":"task Rotate API key is completed. You have done all your tasks. Well done"}
```

Agent rules:
- Mark done only after acceptance criteria in `details` are met.
- If `next-task` exists, queue it as the next candidate for execution.

## 4) Misuse-prevention checklist (must follow)

Before any write operation:
- Confirm correct `app_id`.
- Confirm correct `task_uuid` when updating/completing.
- Ensure payload is JSON and `Content-Type: application/json`.

Before marking done:
- Re-read latest task with `GET /tasks/:id`.
- Ensure remaining checklist items are complete.
- Ensure you are not closing the wrong task due to stale IDs.

When listing:
- Always provide `app_id`.
- If using date range, keep timestamps in `YYYY-MM-DDTHH:MM:SS`.

Error handling:
- `400` => required field missing or invalid filter.
- `404` => task not found for that app scope.

## 5) High-value use cases

1. **Agent execution queue**
   - Poll `GET /tasks?app_id=<agent>&status=new`.
   - Pick first task, process, update progress, mark done.

2. **Human + bot collaboration**
   - Human creates tasks with rich markdown.
   - Bot updates details with progress notes and evidence.
   - Bot marks done and pivots to returned `next-task`.

3. **Incident response**
   - Create one task per mitigation action.
   - Version updates as timeline entries.
   - List by date range after incident for retrospective.

4. **Scheduled maintenance**
   - Pre-create maintenance checklist tasks.
   - Use `search` to locate service-specific tasks quickly.

## 6) Example end-to-end script

```bash
APP_ID="ops-bot"
BASE="http://localhost:5000"

TASK_ID=$(curl -sS -X POST "$BASE/tasks" \
  -H "Content-Type: application/json" \
  -d '{"app_id":"ops-bot","title":"Patch nginx","details":"## Plan\n- patch\n- restart\n- validate"}' | jq -r '.[0]')

curl -sS -X PUT "$BASE/tasks/$TASK_ID" \
  -H "Content-Type: application/json" \
  -d '{"app_id":"ops-bot","details":"## Progress\n- patch complete\n- restart complete\n- validating"}'

curl -sS "$BASE/tasks/$TASK_ID?app_id=$APP_ID"

curl -sS -X POST "$BASE/tasks/$TASK_ID/done" \
  -H "Content-Type: application/json" \
  -d '{"app_id":"ops-bot"}'
```

## 7) FAQ

**Q: Can I update title after creation?**
- No endpoint exists for title changes. Use details versions to record changes, or create a new task if title must differ.

**Q: Can I mark a task back to `new`?**
- No direct endpoint exists. Avoid marking done early.

**Q: Why do I get 404 for a known task UUID?**
- Most likely wrong `app_id` scope.

**Q: How should bots format details?**
- Use structured markdown (`##`, checklists, bullets) so humans can review progress quickly.

**Q: What is the safest way to choose next work?**
- Use `GET /tasks?app_id=<id>&status=new`, then pick oldest/first item from `Task Needs To Be Done`.

**Q: Does list return both done and new by default?**
- Yes, when `status` is omitted.

## 8) Agent behavior policy

- Be explicit and consistent with `app_id` per workflow.
- Never assume completion without verification.
- Prefer idempotent read checks (`GET`) before destructive state transitions (`done`).
- Keep updates concise but meaningful; avoid spammy version growth.
