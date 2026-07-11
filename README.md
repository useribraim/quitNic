# QuitNic

QuitNic is a privacy-conscious native iOS nicotine-quit coach backed by a Python REST service. The iOS 17 client remains useful offline, synchronizes retryable writes exactly once, and obtains bounded coaching responses without exposing an AI credential in the application.

## Engineering highlights

- **Native Apple client:** SwiftUI, SwiftData, observable app state, async URLSession networking, Keychain token storage and local notifications.
- **Offline data integration:** cached progress plus a persistent outbox with idempotency keys, retry classification, relaunch recovery and duplicate-delivery protection.
- **Backend service:** FastAPI, typed Pydantic contracts, SQLAlchemy relational models, Alembic migrations, PostgreSQL and opaque bearer-token authentication with only token hashes persisted.
- **AI safety boundary:** provider-isolated OpenAI adapter, deterministic development provider, bounded context and a fixed urgent-language escalation path.
- **Engineering quality:** 11 backend tests, 17 iOS unit tests and two signed Simulator UI journeys, with client-server GitHub Actions and PostgreSQL migration coverage.

## Current verification

The complete backend check (`ruff`, `mypy`, and `pytest`) passes. The full iOS suite passes repeatedly on an iPhone 16 Pro Simulator, including onboarding, persistence, check-in synchronization, progress, normal coaching and the urgent-language safety response. The non-root Docker image builds, applies its schema migration and returns a healthy runtime response.

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

The Debug build defaults to `http://localhost:8000`. Replace the Release `QUITNIC_API_URL` setting in `ios/project.yml` with the HTTPS production endpoint before generating a release candidate. Replace the example bundle identifier and select your signing team before device distribution.

## Security

Access tokens are random opaque values stored in iOS Keychain; the database stores only HMAC-SHA256 hashes. OpenAI and database credentials are backend-only secrets. Do not commit `.env`, signing files, exports, or production configuration.

## Release status

The project is a verified local release candidate. AWS deployment and external TestFlight distribution have not happened yet; the production endpoint and example bundle identifier must be replaced before release. See [the TestFlight checklist](docs/testflight.md) for the remaining account-dependent work.
