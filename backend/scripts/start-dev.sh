#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR/.."

if [ -x .venv/bin/alembic ]; then
    ALEMBIC=.venv/bin/alembic
    UVICORN=.venv/bin/uvicorn
else
    ALEMBIC=alembic
    UVICORN=uvicorn
fi

"$ALEMBIC" upgrade head
exec "$UVICORN" app.main:app --host "${HOST:-127.0.0.1}" --port "${PORT:-8000}" --reload

