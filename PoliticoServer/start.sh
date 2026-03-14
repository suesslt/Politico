#!/bin/bash
cd "$(dirname "$0")"

# PostgreSQL via Postgres.app
export PATH="/Applications/Postgres.app/Contents/Versions/latest/bin:$PATH"

# Default environment
export DB_HOST="${DB_HOST:-localhost}"
export DB_PORT="${DB_PORT:-5432}"
export DB_USER="${DB_USER:-politico}"
export DB_PASSWORD="${DB_PASSWORD:-politico}"
export DB_NAME="${DB_NAME:-politico}"

LOGFILE="$(pwd)/server.log"

# Kill previous instance on port 8080
lsof -ti:8080 | xargs kill -9 2>/dev/null

echo "Building..."
swift build || exit 1

echo "Starting PoliticoServer on http://localhost:8080"
echo "Logs: $LOGFILE"
echo "  tail -f $LOGFILE"
swift run App serve 2>&1 | tee "$LOGFILE"
