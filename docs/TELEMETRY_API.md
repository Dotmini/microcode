# MicroCode telemetry API

`POST /v1/telemetry/events` receives only opt-in device capability snapshots and product events. The client defaults to disabled and sends no event until the user enables it in **Settings → Privacy & Usage**.

The body is `{ "schemaVersion": 1, "events": [...] }`. Events contain an anonymous installation UUID, app version, Mac model, CPU core counts, RAM, GPU names, Neural Engine availability, macOS/architecture, and the event name. Supported event names are `app_launch`, `mode_opened`, and `telemetry_consent_granted`.

The endpoint rejects source code, prompts, project/file paths, email, serial numbers, hardware UUIDs, arbitrary event names, and arbitrary event properties. Configure `TELEMETRY_LOG_PATH` on persistent server storage.

`GET /api/admin/telemetry/summary` returns aggregate counts only: anonymous installs, event and mode counts, app versions, daily activity, and hardware capability distributions. It requires `Authorization: Bearer <TELEMETRY_ADMIN_TOKEN>`.

`GET /admin/telemetry` serves a dependency-free admin dashboard. It requests the token in the browser and keeps it only in browser session storage; it never puts the token into the URL or server logs. Deploy the backend route to the same host used by the desktop app (for example `api.dotmini.net`), set both `TELEMETRY_ADMIN_TOKEN` and an absolute persistent `TELEMETRY_LOG_PATH`, and rotate the NDJSON file according to your privacy policy.
