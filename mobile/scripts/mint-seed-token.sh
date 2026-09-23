#!/bin/bash
# Mints a long-lived auth token from the local CloudCLI server's own JWT
# secret, so the app can start without anyone typing credentials. Personal
# build only: this reads ~/.cloudcli/auth.db on the machine that runs the
# server.
#
# Usage: scripts/mint-seed-token.sh [lifetime-days]   (default 365)
set -euo pipefail

DB="${CLOUDCLI_DB:-$HOME/.cloudcli/auth.db}"
DAYS="${1:-365}"

if [ ! -f "$DB" ]; then
  echo "找不到数据库：$DB（用 CLOUDCLI_DB 指定）" >&2
  exit 1
fi

node - "$DB" "$DAYS" <<'NODE'
const crypto = require('crypto');
const { execSync } = require('child_process');
const [db, daysArg] = process.argv.slice(2);
const days = Number(daysArg) || 365;
const secret = execSync(`sqlite3 "${db}" "SELECT value FROM app_config WHERE key='jwt_secret';"` )
  .toString()
  .trim();
const user = execSync(`sqlite3 "${db}" "SELECT id, username FROM users ORDER BY id LIMIT 1;"`)
  .toString()
  .trim();
if (!secret || !user.includes('|')) {
  console.error('auth.db 里没有 jwt_secret 或用户，先在网页版完成注册');
  process.exit(1);
}
const [id, username] = user.split('|');
const b64u = (value) => Buffer.from(value).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const header = b64u(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
const payload = b64u(JSON.stringify({ userId: Number(id), username, iat: now, exp: now + days * 86400 }));
const signature = crypto.createHmac('sha256', secret).update(`${header}.${payload}`).digest('base64url');
console.log(`${header}.${payload}.${signature}`);
NODE
