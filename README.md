# OpenTask API

OpenTask is a lightweight REST API for managing tasks across different applications (`app_id`).
It is built with **Perl + Dancer2** and designed for teams or systems that need:

- simple task creation and tracking,
- markdown task details,
- update history (versioned task details),
- status flow (`new` -> `done`),
- fast integration via HTTP.

---

## What is this?

OpenTask is a backend service that stores tasks and exposes CRUD-like operations focused on execution flow:

1. Create a task.
2. Update details as work evolves (each update is versioned).
3. Fetch the latest task state.
4. List tasks with filtering/search.
5. Mark tasks done and suggest the next pending task.

---

## Who is it for?

- Internal tooling teams.
- Automation systems that need a shared task API.
- Small apps that want a self-hosted task service without a full project-management platform.

---

## What problem does it solve?

Many systems need task tracking but do not need the complexity of a full SaaS task manager.
OpenTask provides a small, portable API with:

- **App-level isolation** via `app_id`.
- **Version history** on task updates.
- **Simple status lifecycle** (`new`, `done`).
- **Search/filter/list** endpoints for operational reporting.
- **Docker-ready deployment**.

---

## API Overview

Base URL examples below use:

```bash
http://localhost:5000
```

### 1) Create task

`POST /tasks`

**Request body**
- `app_id` (required)
- `title` (required)
- `details` (required, markdown supported)

```bash
curl -s -X POST http://localhost:5000/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "app_id":"my-app",
    "title":"Build onboarding page",
    "details":"## TODO\n- Create hero section\n- Add CTA"
  }'
```

**Response**

```json
["<task-uuid>"]
```

---

### 2) Update task (versioned)

`PUT /tasks/:task_uuid`

**Request body**
- `app_id` (required)
- `details` (required; new version content)

```bash
curl -s -X PUT http://localhost:5000/tasks/<task-uuid> \
  -H "Content-Type: application/json" \
  -d '{
    "app_id":"my-app",
    "details":"## Updated plan\n- Hero done\n- CTA in progress"
  }'
```

**Response**

```json
{"id":"<task-uuid>","message":"task Build onboarding page has been updated, continue working until finish the whole task please."}
```

---

### 3) Get task (latest version)

`GET /tasks/:task_uuid?app_id=...`

```bash
curl -s "http://localhost:5000/tasks/<task-uuid>?app_id=my-app"
```

Returns latest details version, status, timestamps, and metadata.

---

### 4) List tasks

`GET /tasks?app_id=...`

Optional filters:
- `status=new|done`
- `from=YYYY-MM-DDTHH:MM:SS`
- `to=YYYY-MM-DDTHH:MM:SS`
- `search=keyword`

```bash
curl -s "http://localhost:5000/tasks?app_id=my-app&status=new"
```

```bash
curl -s "http://localhost:5000/tasks?app_id=my-app&from=2026-01-01T00:00:00&to=2026-12-31T23:59:59&search=hero"
```

**Response shape**

```json
{
  "Task Needs To Be Done": [
    {"task-id":"<uuid>","details":"...MD FORMAT...","timestamp":"YYYY-MM-DDTHH:MM:SS"}
  ],
  "Completed Tasks": [
    {"task-id":"<uuid>","details":"...MD FORMAT...","timestamp":"YYYY-MM-DDTHH:MM:SS"}
  ]
}
```

---

### 5) Mark task as done

`POST /tasks/:task_uuid/done`

**Request body**
- `app_id` (required)

```bash
curl -s -X POST http://localhost:5000/tasks/<task-uuid>/done \
  -H "Content-Type: application/json" \
  -d '{"app_id":"my-app"}'
```

Possible responses:

```json
{"this-task":"<uuid>","message":"task Build onboarding page is completed, move on to the next task <next-uuid>","next-task":"<next-uuid>"}
```

or

```json
{"this-task":"<uuid>","message":"task Build onboarding page is completed. You have done all your tasks. Well done"}
```

---

## Task status rules

- New task -> `status = new`
- Completed task -> `status = done`

---

## Local setup (without Docker)

Requirements:
- Perl 5.38+ (or compatible)
- `cpanm`

Install dependencies and run:

```bash
cpanm --installdeps .
plackup -Ilib -p 5000 app.psgi
```

---

## Docker setup

### Using Docker Compose

```bash
docker compose up --build
```

API will be available at `http://localhost:5000`.

The compose setup mounts `./data` into the container, so task data persists on host at:

- `data/tasks.json`

### Using Docker directly

```bash
docker build -t opentask:local .
docker run --rm -p 5000:5000 -e TASK_STORAGE_FILE=/app/data/tasks.json -v "$(pwd)/data:/app/data" opentask:local
```

---

## CI/CD image publish

GitHub Actions workflow publishes images to Docker Hub repository:

- `michaelpc/opentask`

Set these repository secrets:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

---

## Notes

- Storage is JSON-file based (`TASK_STORAGE_FILE`, default `data/tasks.json`).
- This project is intentionally simple and easy to self-host.
