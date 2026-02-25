# AGENT.md (Bot/Agent Playbook)

## Mandatory request/response contract

- Write endpoints (`POST /tasks`, `PUT /tasks/:id`, `POST /tasks/:id/done`) must be sent as **multipart/form-data**.
- API responses are **YAML** (`text/yaml`).
- Use `code-name` (not `app_id`).
- Include `username` in every request.
- `username` must exist in `user.yml` under `users` keys.

## User validation source

`user.yml` format:

```yaml
users:
  michael-sad987f9: michael
  david-9asd8f7: david
```

Use one of the keys as `username`.

## Required fields by operation

1) Create (`POST /tasks`)
- `username`
- `code-name`
- `title`
- `details`

2) Update (`PUT /tasks/:id`)
- `username`
- `code-name`
- `details`

3) Get (`GET /tasks/:id`)
- query: `username`
- query: `code-name`

4) List (`GET /tasks`)
- query: `username`
- query: `code-name`
- optional: `status`, `from`, `to`, `search`

5) Done (`POST /tasks/:id/done`)
- `username`
- `code-name`

## Safe usage examples

### Create
```bash
curl -sS -X POST http://localhost:5000/tasks \
  -F "username=michael-sad987f9" \
  -F "code-name=ops-alpha" \
  -F "title=Patch nginx" \
  -F $'details=## Plan\n- patch\n- restart\n- verify'
```

### Update
```bash
curl -sS -X PUT http://localhost:5000/tasks/<task-uuid> \
  -F "username=michael-sad987f9" \
  -F "code-name=ops-alpha" \
  -F $'details=## Progress\n- patch done\n- restarting now'
```

### Get
```bash
curl -sS "http://localhost:5000/tasks/<task-uuid>?username=michael-sad987f9&code-name=ops-alpha"
```

### List
```bash
curl -sS "http://localhost:5000/tasks?username=michael-sad987f9&code-name=ops-alpha&status=new"
```

### Done
```bash
curl -sS -X POST http://localhost:5000/tasks/<task-uuid>/done \
  -F "username=michael-sad987f9" \
  -F "code-name=ops-alpha"
```

## Misuse prevention

- Never send JSON for write calls; use multipart form.
- Never send `app_id`; use `code-name`.
- Always pass a valid `username` from `user.yml` keys.
- Confirm latest task state with `GET` before calling `done`.
- Preserve returned task UUID exactly; do not reconstruct it.

## Storage expectation

- `/opentask/<code-name>/tasks/YYYYMMDDTHHMMSS-<UUID>.md`
- `/opentask/<code-name>/done/YYYYMMDDTHHMMSS-<UUID>.md`

## FAQ

**Q: I get 403 username invalid.**
A: Username key is missing from `user.yml` under `users`.

**Q: I sent JSON and got missing fields.**
A: Use multipart form fields (`-F` in curl).

**Q: Can I still use `code_name` instead of `code-name`?**
A: Prefer `code-name`; API also accepts `code_name` for compatibility.

**Q: What format are responses?**
A: YAML for success and error payloads.
