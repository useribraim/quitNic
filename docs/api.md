# API contract

All routes except registration and health require `Authorization: Bearer <token>`. JSON uses snake_case and timestamps use ISO 8601 UTC. Errors have the shape `{"error":{"code":"...","message":"..."}}`.

| Method | Route | Purpose |
|---|---|---|
| POST | `/v1/devices/register` | Create an anonymous account and one bearer token |
| GET/PUT | `/v1/quit-plan` | Read or replace the device quit plan |
| GET/POST | `/v1/check-ins` | Page through or create craving events |
| POST | `/v1/coaching/messages` | Obtain a bounded coaching reply |
| GET | `/v1/progress` | Calculate canonical progress and next milestone |
| DELETE | `/v1/account` | Permanently delete the account and related records |
| GET | `/health` | App Runner health probe |

POST check-ins require an `Idempotency-Key` header of 8–80 characters. Check-in history accepts `limit` (1–100) and an opaque `cursor`. Generated schemas and examples are available from `/docs` and `/openapi.json`.

