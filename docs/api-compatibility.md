# TeslaMateApi compatibility (historical)

**The app no longer speaks TeslaMateApi.** Its client was removed in 1.6.0 once
Tessalytics Backend covered every endpoint it had; keeping two clients meant two
code paths for one job and every fix made twice. See `docs/architecture.md` for
the current shape.

This document is kept because the DTOs still mirror the field names below.
`BackendModels.swift` maps the backend's own response shapes onto them, so this is
the reference for why `odometerDetails`, `batteryDetails` and their siblings are
named and nested the way they are.

The original model review was performed against TeslaMateApi `main` commit
`3e158df077165237130072c82d07878ab448f4f8` on August 19, 2026.

Supported read endpoints:

- `GET /api/ping`
- `GET /api/v1/cars` and `/cars/{id}`
- `GET /api/v1/cars/{id}/status`
- `GET /api/v1/cars/{id}/battery-health`
- `GET /api/v1/cars/{id}/drives` and `/drives/{driveId}`
- `GET /api/v1/cars/{id}/charges`, `/charges/current`, and `/charges/{chargeId}`
- `GET /api/v1/cars/{id}/updates`
- `GET /api/v1/globalsettings`

List pagination is one-indexed. Tessalytics sends `page` and `show=30`, plus supported date and location filters. Drive distance filters are part of the API contract and can be added to the filter UI without changing transport architecture.

The decoder uses one global `.convertFromSnakeCase` strategy and a reusable `Envelope<T>`. Optional transport fields tolerate `null`, absence, and unknown future keys. Date parsing accepts RFC 3339 offsets and ISO 8601 with or without fractional seconds, but rejects years before 1900 and the known invalid scheduled-charging sentinel.

Every request sends an explicit `Tessalytics/<version>` User-Agent because some protected deployments reject unidentified clients at the reverse-proxy edge. A successful `/charges/current` response containing a top-level `error` instead of `data` is treated as no active charging session rather than as incompatible JSON.

TeslaMateApi versions and database completeness differ. Upstream response structs sometimes expose non-optional primitives for data that may be absent in practice; Tessalytics deliberately models display-only values as optional and never substitutes zero for missing values.

TeslaMateApi command, wake-up, and logging-control endpoints are not represented in the TeslaMate client protocol or UI. Optional direct controls use a separate Owner API session, always require device-owner authentication, and never wake a vehicle automatically.
