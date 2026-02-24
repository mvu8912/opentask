# OpenTask API (Dancer2)

Simple task REST API in Perl Dancer2.

## Run locally

```bash
cpanm --installdeps .
plackup -Ilib -p 5000 app.psgi
```

## Endpoints

- `POST /tasks` - create task (`app_id`, `title`, `details`) returns `[$uuid]`
- `PUT /tasks/:id` - update task (`app_id`, `details`) and creates a new version
- `GET /tasks/:id?app_id=...` - get latest version of task
- `GET /tasks?app_id=...&status=new|done&from=YYYY-MM-DDTHH:MM:SS&to=...&search=...`
- `POST /tasks/:id/done` - mark task done (`app_id`)

Task status values are `new` and `done`.
