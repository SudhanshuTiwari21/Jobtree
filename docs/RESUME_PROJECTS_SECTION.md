# Resume — Projects Section (JobTree)

Use the content below in your **Projects** section. Copy the bullet format or the paragraph version depending on your resume style.

---

## JobTree — Salon Hiring Platform (Full-Stack)

**Role:** Full-Stack Developer (or Backend / Mobile — pick one)  
**Tech:** Flutter (iOS/Android), Node.js, Express, PostgreSQL (Neon), AWS S3, Firebase Cloud Messaging, JWT, Twilio  
**Duration:** [Add your dates, e.g. Jan 2024 – Present]

### Short blurb (1–2 lines)

Full-stack mobile and backend for a B2B salon hiring app: job seekers apply and get shortlisted; salon owners post jobs, manage candidates, and conduct masked calls. Backend designed for scale with connection pooling, health checks, and planned read replicas and Redis caching.

---

### Bullet points (pick 4–6)

- **Backend system design:** Designed and built a production-ready REST API (Node.js, Express) with layered architecture: route → service → database; connection pooling (PostgreSQL/Neon), migrations, transaction support, and detailed health checks (DB latency, pool stats) for deploy and monitoring.
- **Scalability & infra:** Architecture supports horizontal scaling with **PostgreSQL read replicas** for read-heavy workloads and **Redis** for session/store caching and rate-limit state (planned); connection pool tuning and statement timeouts to handle serverless DB (Neon) and future replica routing.
- **Auth & security:** Phone/OTP auth (Twilio SMS), JWT access/refresh with secure storage; rate limiting (express-rate-limit), Helmet, CORS, and express-validator on inputs; presigned S3 URLs for uploads so backend never handles file bytes.
- **Real-time & background:** Firebase Cloud Messaging for push (FCM/APNS); cron (node-cron) for interview reminders; Twilio-based call masking for owner–candidate calls; notification log and read state in DB with paginated APIs.
- **Data & APIs:** REST for auth, salon profile, jobs CRUD, applications pipeline (Applied → Shortlisted → Interview → Hired/Rejected), notifications, device registration, and support; presigned media upload and media records in PostgreSQL.
- **Mobile (Flutter):** Cross-platform app for seekers (job feed, apply, notifications) and owners (post jobs, candidate list, shortlist/hire, profile with photo upload); deep links from push; secure token storage and API service layer.

---

### Paragraph version (if you prefer prose)

**JobTree** is a full-stack salon hiring platform: job seekers discover and apply to salon jobs; owners post jobs, manage candidates, and communicate via masked calls.  
**Backend:** Designed and implemented a production-ready Node.js/Express REST API with a clear layered design (routes → services → DB). Uses **PostgreSQL** (Neon) with connection pooling, migrations, and transaction helpers; detailed health checks expose DB latency and pool stats. The system is designed to scale via **PostgreSQL read replicas** for read-heavy traffic and **Redis** for session and cache (planned). Security includes OTP auth (Twilio SMS), JWT access/refresh, rate limiting, Helmet, CORS, and input validation; media uploads use presigned S3 URLs. **Real-time and background:** Firebase Cloud Messaging for push (iOS/Android), node-cron for interview reminders, Twilio for masked calls; notifications and device registration are persisted with paginated APIs. **Mobile:** Flutter app for both seeker and owner flows (job feed, applications, candidate pipeline, profile photo upload, push deep links). Deployed backend on EC2 with PM2 and Nginx.

---

### Keywords to keep in the resume (ATS / scanning)

Backend system design, REST API, Node.js, Express, PostgreSQL, connection pooling, migrations, read replicas, Redis, scalability, JWT, OTP, rate limiting, AWS S3, presigned URLs, Firebase (FCM), cron, Twilio, Flutter, iOS, Android, health checks, PM2, Nginx.

---

### Note on replica & Redis

You haven’t implemented replica or Redis yet; the bullets and paragraph above phrase it as “architecture supports” / “designed for” / “planned” so it’s accurate. When you add them later, you can switch to past tense (“Introduced read replicas and Redis for…”).
