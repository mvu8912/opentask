# OpenTask API

OpenTask is a lightweight task REST API in Perl Dancer2 for agents and internal automation.

## What changed
- Requests for write operations are expected as `multipart/form-data`.
- Responses are returned in `YAML` format.
- `app_id` is replaced by `code-name`.
- New required field: `username`.
- `username` must exist in `user.yml`.

## User validation

`user.yml` example:

```yaml
users:
  michael-sad987f9: michael
  david-9asd8f7: david
```

The API validates request `username` against keys under `users`.

## Storage layout

Tasks are stored on filesystem (default root `/opentask`):

- `/opentask/<code-name>/tasks/YYYYMMDDTHHMMSS-<UUID>.md`
- `/opentask/<code-name>/done/YYYYMMDDTHHMMSS-<UUID>.md`

## Run locally

```bash
cpanm --installdeps .
plackup -Ilib -p 5000 app.psgi
```

## Docker

```bash
docker compose up --build
```

Compose mounts `./data` to `/opentask`.

## API examples

Base URL:

```bash
http://localhost:5000
```

### Create task

```bash
curl -sS -X POST http://localhost:5000/tasks \
  -F "username=michael-sad987f9" \
  -F "code-name=ops-alpha" \
  -F "title=Rotate API key" \
  -F $'details=## Steps\n- notify\n- rotate\n- verify'
```

### Update task

```bash
curl -sS -X PUT http://localhost:5000/tasks/<task-uuid> \
  -F "username=michael-sad987f9" \
  -F "code-name=ops-alpha" \
  -F $'details=## Progress\n- rotate done\n- verification running'
```

### Get task

```bash
curl -sS "http://localhost:5000/tasks/<task-uuid>?username=michael-sad987f9&code-name=ops-alpha"
```

### List tasks

```bash
curl -sS "http://localhost:5000/tasks?username=michael-sad987f9&code-name=ops-alpha"
```

Filter by status:

```bash
curl -sS "http://localhost:5000/tasks?username=michael-sad987f9&code-name=ops-alpha&status=new"
```

### Mark done

```bash
curl -sS -X POST http://localhost:5000/tasks/<task-uuid>/done \
  -F "username=michael-sad987f9" \
  -F "code-name=ops-alpha"
```

## Response format

All responses are YAML (`text/yaml`).
