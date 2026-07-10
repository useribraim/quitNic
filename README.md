# QuitNic

QuitNic is a privacy-conscious native iOS nicotine-quit coach. The iOS 17 app works offline for progress and craving check-ins, synchronizes through a token-protected FastAPI service, and obtains bounded coaching responses without placing an AI credential in the application.

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

See [docs/architecture.md](docs/architecture.md) and [docs/testflight.md](docs/testflight.md) for the implementation and release process.
