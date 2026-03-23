#!/bin/bash
cd "$(dirname "$0")"

# PostgreSQL via Postgres.app
export PATH="/Applications/Postgres.app/Contents/Versions/latest/bin:$PATH"

# Default environment
export DB_HOST="${DB_HOST:-192.168.1.144}"
export DB_PORT="${DB_PORT:-5432}"
export DB_USER="${DB_USER:-politscore}"
export DB_PASSWORD="${DB_PASSWORD:-politscore}"
export DB_NAME="${DB_NAME:-politscore}"

LOGFILE="$(pwd)/server.log"

# Kill previous instance on port 8080
lsof -ti:8080 | xargs kill -9 2>/dev/null

echo "Building..."
swift build || exit 1

LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "localhost")
echo "Starting PoliticoServer"
echo "  Local:   http://localhost:8080"
echo "  Network: http://$LOCAL_IP:8080"
echo "  Logs:    $LOGFILE"
swift run App serve --hostname 0.0.0.0 --port 8080 2>&1 | tee "$LOGFILE"
