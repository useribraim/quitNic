# QuitNic

QuitNic is a privacy-conscious native iOS nicotine-quit coach backed by a Python REST service. The iOS 17 client remains useful offline, synchronizes retryable writes exactly once, and obtains bounded coaching responses without exposing an AI credential in the application.

## Engineering highlights

- **Native Apple client:** SwiftUI, SwiftData, observable app state, async URLSession networking, Keychain token storage and local notifications.
- **Offline data integration:** cached progress plus a persistent outbox with idempotency keys, retry classification, relaunch recovery and duplicate-delivery protection.
- **Backend service:** FastAPI, typed Pydantic contracts, SQLAlchemy relational models, Alembic migrations, PostgreSQL and opaque bearer-token authentication with only token hashes persisted.
- **AI safety boundary:** provider-isolated OpenAI adapter, deterministic development provider, bounded context and a fixed urgent-language escalation path.
- **Engineering quality:** backend contract tests, iOS unit tests and signed Simulator journeys cover the core quit loop, offline retry, correction/deletion, accessibility audits and accessibility-XXXL layouts, with client-server GitHub Actions and PostgreSQL migration coverage.

## Current verification

The latest focused verification passes on an iPhone 16 Pro Simulator for the canonical Today/Journey loop, Quick Log draft recovery, Accessibility XXXL keyboard use, history correction/deletion, calm offline status and ordinary-log Undo. Backend API tests pass for idempotent create/update/delete, and the iOS outbox tests pass for replacement and retry-safe deletion. Simulator performance baselines are documented in `docs/performance-baselines.md`. The non-root Docker image builds, applies its schema migration and returns a healthy runtime response.

See [the architecture](docs/architecture.md), [API contract](docs/api.md), [test matrix](docs/testing.md), and [deployment design](docs/deployment.md) for implementation details.

## Repository layout

- `ios/` — SwiftUI, SwiftData, URLSession, Keychain, local notifications, unit tests, and UI tests.
- `backend/` — FastAPI, SQLAlchemy, Alembic, PostgreSQL, OpenAI adapter, and API tests.
- `infrastructure/` — AWS App Runner/RDS CloudFormation template.
- `docs/` — architecture, API, deployment, privacy, testing, and TestFlight checklists.

## Local development

### API

```sh
cp backend/.env.example backend/.env
docker compose up --build
curl http://localhost:8000/health
```

Interactive API documentation is available at `http://localhost:8000/docs`. Development uses deterministic coaching when no OpenAI key is configured. Set `COACHING_PROVIDER=openai` and `OPENAI_API_KEY` in `.env` to exercise the production adapter.

For lightweight development without Docker, install the backend dependencies once and use the migration-safe startup command:

```sh
cd backend
python3 -m venv .venv
.venv/bin/pip install -e '.[dev]'
./scripts/start-dev.sh
```

The script applies pending Alembic migrations before starting the reload server, preventing the app from connecting to an empty local database.

### iOS

Install full Xcode and XcodeGen, then:

```sh
cd ios
xcodegen generate
open QuitNic.xcodeproj
```

The Debug build defaults to `http://localhost:8000`. Release builds use the HTTPS App Runner endpoint configured in `ios/project.yml`. Before each new upload, verify that endpoint and the full anonymous-account lifecycle from the signed archive on a physical device, and confirm the bundle identifier and signing team match the App Store Connect record.

## Security

Access tokens are random opaque values stored in iOS Keychain; the database stores only HMAC-SHA256 hashes. OpenAI and database credentials are backend-only secrets. Do not commit `.env`, signing files, exports, or production configuration.

## Release status

As of September 2026, Apple has approved QuitNic 1.0.0 through Beta App Review, and the build is distributed to external testers through TestFlight. Request tester access at [ibraim.ie/quitNic](https://ibraim.ie/quitNic).

The [TestFlight checklist](docs/testflight.md) records the release procedure for subsequent builds. Remaining product work is tracked in `docs/product-improvement-audit.md`.
