# OpenTask API

OpenTask is a lightweight task API in Perl/Dancer2 with filesystem storage.

## Core behavior

- Write requests use `multipart/form-data`.
- Responses are YAML (`text/yaml`).
- Use `code-name` (replaces `app_id`).
- Every request must include `username`.
- No dedicated `title` field; include title/header inside markdown `details`.
- Tasks are stored on filesystem:
  - `/opentask/<code-name>/tasks/YYYYMMDDTHHMMSS-<UUID>.md`
  - `/opentask/<code-name>/done/YYYYMMDDTHHMMSS-<UUID>.md`

## users.yml (required)

The app validates incoming `username` against keys in `users.yml`.

```yaml
users:
  michael-sad987f9: michael
  david-9asd8f7: david
```

How it is linked to the app:
- Default path is `users.yml` in app working directory.
- Override with `USER_FILE`.
- In Docker Compose, mount file and set `USER_FILE=/config/users.yml`.

## Run locally

```bash
cpanm --installdeps .
plackup -Ilib -p 5000 app.psgi
```

## Docker quick start

```bash
docker compose up --build
```

## Docker Compose integration snippet

```yaml
services:
  opentask:
    image: michaelpc/opentask:latest
    ports:
      - "5000:5000"
    environment:
      TASK_STORAGE_ROOT: /opentask
      USER_FILE: /config/users.yml
    volumes:
      - ./opentask-data:/opentask
      - ./users.yml:/config/users.yml:ro
    restart: unless-stopped
```

## API examples

Base URL: `http://localhost:5000`

### Create task

```bash
curl -sS -X POST http://localhost:5000/tasks \
  -F "username=michael-sad987f9" \
  -F "code-name=ops-alpha" \
  -F $'details=# Rotate API key\n\n- notify\n- rotate\n- verify'
```

### Update task

```bash
curl -sS -X PUT http://localhost:5000/tasks/<task-uuid> \
  -F "username=michael-sad987f9" \
  -F "code-name=ops-alpha" \
  -F $'details=# Rotate API key (progress)\n\n- rotate done\n- verification running'
```

### Get task

```bash
curl -sS "http://localhost:5000/tasks/<task-uuid>?username=michael-sad987f9&code-name=ops-alpha"
```

### List tasks

```bash
curl -sS "http://localhost:5000/tasks?username=michael-sad987f9&code-name=ops-alpha"
```

### Search tasks (regex)

Backend compiles `search` as regex and checks each task file's markdown `details`.

```bash
curl -sS "http://localhost:5000/tasks?username=michael-sad987f9&code-name=ops-alpha&search=rotate|verify"
```

### Get all code-names summary

Returns each code-name as a YAML key with `completed` and `in_progress` counts.

```bash
curl -sS "http://localhost:5000/code-names"
```

### Mark done

```bash
curl -sS -X POST http://localhost:5000/tasks/<task-uuid>/done \
  -F "username=michael-sad987f9" \
  -F "code-name=ops-alpha"
```

## Sorting

List results are sorted by timestamp from **newest to oldest**.
