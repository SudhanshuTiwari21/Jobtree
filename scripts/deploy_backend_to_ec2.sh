#!/usr/bin/env bash
# Deploy Jobtree backend to EC2: tarball via SCP, extract on server, npm install, migrate, PM2.
#
# Usage (from repo root):
#   ./scripts/deploy_backend_to_ec2.sh ubuntu@13.201.127.250 ./Admin.pem
# First-time on a fresh Ubuntu box, also install Node 20 + PM2:
#   ./scripts/deploy_backend_to_ec2.sh ubuntu@13.201.127.250 ./Admin.pem --bootstrap
#
# Requires:
#   - backend/.env present locally (copied into the tarball — never commit .env)
#   - Security group: TCP 22 (SSH), 3000 (API) or 80/443 if you use Nginx

set -euo pipefail

usage() {
  echo "Usage: $0 <user@host> <path-to.pem> [--bootstrap]"
  echo "  --bootstrap  Install Node.js 20 + PM2 on the server (run once on a new instance)"
  exit 1
}

[[ $# -lt 2 ]] && usage

TARGET="$1"
PEM="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
BOOTSTRAP=false
[[ "${3:-}" == "--bootstrap" ]] && BOOTSTRAP=true

if [[ ! -f "$PEM" ]]; then
  echo "PEM not found: $PEM"
  exit 1
fi

chmod 400 "$PEM" 2>/dev/null || true

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$REPO_ROOT/backend"
ARCHIVE="/tmp/jobtree-backend-deploy-$$.tar.gz"
REMOTE_ARCHIVE="jobtree-backend-deploy.tar.gz"

if [[ ! -f "$BACKEND/.env" ]]; then
  echo "Missing $BACKEND/.env — create it before deploy (DATABASE_URL, JWT_SECRET, etc.)."
  exit 1
fi

echo "==> Packing backend (excludes node_modules, .git)..."
(
  cd "$BACKEND"
  tar -czf "$ARCHIVE" \
    --exclude=node_modules \
    --exclude=.git \
    .
)

echo "==> SCP archive to $TARGET ..."
scp -i "$PEM" -o StrictHostKeyChecking=accept-new "$ARCHIVE" "$TARGET:~/$REMOTE_ARCHIVE"
rm -f "$ARCHIVE"

SSH=(ssh -i "$PEM" -o StrictHostKeyChecking=accept-new "$TARGET")

if $BOOTSTRAP; then
  echo "==> Bootstrap: Node.js 20 + PM2 (requires sudo on server)..."
  "${SSH[@]}" bash -s << 'BOOTSTRAP_EOF'
set -euo pipefail
sudo apt-get update -y
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi
node -v
npm -v
sudo npm install -g pm2
pm2 -v
BOOTSTRAP_EOF
fi

echo "==> Extract, npm install, migrate, PM2 ..."
"${SSH[@]}" bash -s -- "$REMOTE_ARCHIVE" << 'REMOTE_EOF'
set -euo pipefail
REMOTE_ARCHIVE="$1"
mkdir -p ~/backend
tar -xzf ~/"$REMOTE_ARCHIVE" -C ~/backend
rm -f ~/"$REMOTE_ARCHIVE"
cd ~/backend
npm install
npm run db:migrate
if pm2 describe jobtree-api >/dev/null 2>&1; then
  pm2 restart jobtree-api
else
  pm2 start src/server.js --name jobtree-api
fi
pm2 save
echo ""
echo "PM2 status:"
pm2 list
echo ""
echo "Health (from server):"
curl -sS http://127.0.0.1:3000/api/health || true
echo ""
REMOTE_EOF

echo ""
echo "Done. From your laptop test: curl http://$(echo "$TARGET" | sed 's/.*@//')/api/health"
echo "If PM2 does not start on reboot, SSH in once and run: pm2 startup && pm2 save"
