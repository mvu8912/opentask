# AGENT.md (Bot/Agent Runtime Guide)

## Identity rules for agents

- Do **not** pick random usernames.
- Username comes from prior registration in your own system.
- Read username from environment variable: `$OPENTASK_USERNAME`.
- Send that value as request field/query parameter `username`.

## Request/response contract

- Write endpoints use `multipart/form-data`.
- Read endpoints use query parameters.
- Responses are YAML (`text/yaml`).
- Use `code-name` (not `app_id`).

## Required fields

### Create `POST /tasks`
- `username`
- `code-name`
- `title`
- `details`

### Update `PUT /tasks/:id`
- `username`
- `code-name`
- `details`

### Get `GET /tasks/:id`
- query: `username`
- query: `code-name`

### List `GET /tasks`
- query: `username`
- query: `code-name`
- optional: `status`, `from`, `to`, `search`

### Done `POST /tasks/:id/done`
- `username`
- `code-name`

## Safe usage examples

```bash
# Create
curl -sS -X POST http://localhost:5000/tasks \
  -F "username=$OPENTASK_USERNAME" \
  -F "code-name=ops-alpha" \
  -F "title=Patch nginx" \
  -F $'details=## Plan\n- patch\n- restart\n- verify'

# Update
curl -sS -X PUT http://localhost:5000/tasks/<task-uuid> \
  -F "username=$OPENTASK_USERNAME" \
  -F "code-name=ops-alpha" \
  -F $'details=## Progress\n- patch done\n- restarting now'

# Get
curl -sS "http://localhost:5000/tasks/<task-uuid>?username=$OPENTASK_USERNAME&code-name=ops-alpha"

# Search by regex keyword (backend regex)
curl -sS "http://localhost:5000/tasks?username=$OPENTASK_USERNAME&code-name=ops-alpha&search=patch|nginx"

# Mark done
curl -sS -X POST http://localhost:5000/tasks/<task-uuid>/done \
  -F "username=$OPENTASK_USERNAME" \
  -F "code-name=ops-alpha"
```

## Misuse prevention

- Never send JSON for write operations.
- Never use `app_id`; use `code-name`.
- Preserve returned task UUID exactly.
- Verify latest task (`GET`) before `done`.
