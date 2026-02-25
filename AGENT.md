# AGENT.md (Bot/Agent Runtime Guide)

## Identity rules for agents

- Do **not** pick random usernames.
- Username comes from prior registration in your own system.
- Read username from environment variable: `$OPENTASK_USERNAME`.
- Send that value in `username` for every request.

## Contract

- Write endpoints use `multipart/form-data`.
- Responses are YAML (`text/yaml`).
- Use `code-name` (not `app_id`).
- There is no separate `title` field; put title/header in markdown `details`.

## Required fields

### Create `POST /tasks`
- `username`
- `code-name`
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
- optional: `status`, `from`, `to`, `search` (regex)

### Done `POST /tasks/:id/done`
- `username`
- `code-name`

### Code-name summary `GET /code-names`
- no auth fields required
- returns YAML map: `code-name -> {completed, in_progress}`

## Safe usage examples

```bash
# Create
curl -sS -X POST http://localhost:5000/tasks \
  -F "username=$OPENTASK_USERNAME" \
  -F "code-name=ops-alpha" \
  -F $'details=# Patch nginx\n\n- patch\n- restart\n- verify'

# Regex search
curl -sS "http://localhost:5000/tasks?username=$OPENTASK_USERNAME&code-name=ops-alpha&search=patch|restart"

# Code-name summary
curl -sS "http://localhost:5000/code-names"
```

## Misuse prevention

- Never send JSON for write operations.
- Never send `app_id`; use `code-name`.
- Preserve returned task UUID exactly.
- Verify latest task before calling `done`.
