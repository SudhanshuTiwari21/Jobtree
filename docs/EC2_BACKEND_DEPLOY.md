# Deploy backend to EC2 (SCP + PM2)

## What the script does

1. Builds a **tar.gz** of `backend/` (includes **`.env`**, excludes `node_modules` and `.git`).
2. **SCP**s it to the server home directory.
3. On the server: extracts to **`~/backend`**, runs **`npm install`**, **`npm run db:migrate`**, starts or restarts **`pm2`** process **`jobtree-api`**.

## One-time: AWS security group

Open inbound:

- **22** — SSH (restrict to your IP if possible).
- **3000** — Node API (or only **80/443** if you terminate TLS at Nginx and proxy to `127.0.0.1:3000`).

## First deploy on a new Ubuntu instance

From the **jobtree repo root** (where `backend/.env` exists):

```bash
chmod +x scripts/deploy_backend_to_ec2.sh

# First time: add --bootstrap to install Node 20 + PM2 via apt
./scripts/deploy_backend_to_ec2.sh ubuntu@YOUR_PUBLIC_IP ./Admin.pem --bootstrap

# Later deploys (code + .env updates only):
./scripts/deploy_backend_to_ec2.sh ubuntu@YOUR_PUBLIC_IP ./Admin.pem
```

Replace `YOUR_PUBLIC_IP` (e.g. `13.201.127.250`) and the path to your **`.pem`** (not inside git if possible).

## `backend/.env` on the server

The script ships your **local** `backend/.env` inside the tarball. Before deploy, set at least:

- `DATABASE_URL` — Neon (or Postgres) reachable from EC2.
- `JWT_SECRET` — strong secret in production.
- `NODE_ENV=production` when you are live.
- `BASE_URL` or `TWILIO_WEBHOOK_BASE_URL` — use your public API URL if you use Twilio webhooks.

## PM2 on reboot

After the first successful `pm2 start`, run once on the server:

```bash
pm2 startup
# Run the command it prints (sudo env PATH=...)
pm2 save
```

## Manual health check

```bash
curl http://YOUR_PUBLIC_IP:3000/api/health
```

## Frontend

Point `ApiConfig.baseUrl` in `lib/services/api_service.dart` to `http://YOUR_PUBLIC_IP:3000/api` (or `https://...` once you add TLS), then rebuild the app.

## Security

- Do **not** commit **`Admin.pem`** or **`.env`**.
- Prefer **HTTPS** (Nginx + Let’s Encrypt) for production Android builds.
