# AppFlowy Podman Deployment

A **podman-compose** setup to run [AppFlowy](https://github.com/AppFlowy-IO/AppFlowy) with **Postgres**, **Caddy** (for SSL), and **automated backups to S3**.

## Table of Contents

1. [Overview](#overview)  
2. [Requirements](#requirements)  
3. [Repository Structure](#repository-structure)  
4. [Getting Started](#getting-started)  
   - [1. Clone & Submodules](#1-clone--submodules)  
   - [2. Configure `.env`](#2-configure-env)  
   - [3. Build AppFlowy (Optional)](#3-build-appflowy-optional)  
   - [4. Run Podman-Compose](#4-run-podman-compose)  
5. [Automated Database Backups](#automated-database-backups)  
   - [How It Works](#how-it-works)  
   - [S3 Cleanup](#s3-cleanup)  
   - [Restore a Backup](#restore-a-backup)  
6. [Caddy for SSL/TLS](#caddy-for-ssltls)  
7. [Advanced Tips](#advanced-tips)  
   - [Using S3 Lifecycle Policies](#using-s3-lifecycle-policies)  
   - [Customizing the Backup Schedule](#customizing-the-backup-schedule)  
8. [Updating AppFlowy Source](#updating-appflowy-source)  
9. [Contributing](#contributing)  
10. [License](#license)

---

## Overview

This repository provides a **Podman**-based deployment for AppFlowy, a customizable productivity suite. It includes:

- **Postgres** for database storage.  
- **AppFlowy** (Rust backend + Flutter web) built from source or from an existing Docker/Podman image.  
- **Caddy** for automated HTTPS certificates (via Let’s Encrypt).  
- A **backup** service that dumps the Postgres DB to `.sql`, then uploads it to **Amazon S3**, and removes older backups automatically.

This setup is ideal for self-hosted scenarios where you want a secure, SSL-enabled AppFlowy instance with a daily backup routine.

---

## Requirements

1. **Podman** (or Docker) and **podman-compose** installed.  
2. **Git**.  
3. **A domain** pointing to the server’s public IP (for Caddy SSL).  
4. **AWS account** and an S3 bucket (for backups).  
5. (Optional) **Rust** + **Flutter** if you plan to build AppFlowy from source directly on the host or within Docker/Podman.

---

## Repository Structure

```
appflowy-podman-deployment
├─ appflowy/                # (Submodule or cloned source of AppFlowy)
├─ backup/
│  ├─ Dockerfile            # Alpine image with PostgreSQL client & AWS CLI
│  ├─ backup-cron.sh        # Cron job setup script
│  └─ backup.sh             # Main backup script (pg_dump & S3 upload)
├─ .gitignore               # Ignore secrets, build artifacts, etc.
├─ .env.example             # Example environment variables
├─ build_appflowy.sh        # (Optional) Script to clone/build AppFlowy from source
├─ Caddyfile                # Caddy reverse proxy config
├─ podman-compose.yml       # Podman Compose file defining all containers
└─ README.md                # This readme
```

---

## Getting Started

### 1. Clone & Submodules

```bash
git clone https://github.com/your-username/appflowy-podman-deployment.git
cd appflowy-podman-deployment

# (If you're using git submodules instead of a direct clone approach)
git submodule update --init --recursive
```

> If you’re **not** using submodules, you can remove the `appflowy/` folder and let `build_appflowy.sh` clone AppFlowy on-the-fly.

### 2. Configure `.env`

1. Copy `.env.example` to `.env`:  
   ```bash
   cp .env.example .env
   ```
2. **Edit** `.env` with **real** values:
   - **Postgres** credentials: `APPFLOWY_DB_USER`, `APPFLOWY_DB_PASS`, `APPFLOWY_DB_NAME`.  
   - **AppFlowy** secrets (like `APPFLOWY_BACKEND__SECRET_KEY`).  
   - **Caddy** domain (`CADDY_DOMAIN`) and email (`CADDY_EMAIL`) for Let’s Encrypt.  
   - **AWS** credentials & bucket info: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, `S3_BUCKET_NAME`.

> **Important**: Keep `.env` out of version control since it contains secrets.

### 3. Build AppFlowy (Optional)

If you want to **build** from source locally (instead of using a prebuilt image or Dockerfile that does it for you):

```bash
./build_appflowy.sh
```

This script (by default) will:

1. Clone the AppFlowy repo to `appflowy/` (if not already existing).  
2. Build the **Rust backend** (`cargo build --release`).  
3. Build the **Flutter web** client (`flutter build web`).

Adjust the script as needed for your environment.

### 4. Run Podman-Compose

From the root of this repo:

```bash
podman-compose up -d
```

Containers launched:

1. **postgres**: Stores AppFlowy data.  
2. **appflowy**: The AppFlowy backend + web. By default, it’s built from the Dockerfile in `docker/` or simply references the compiled artifacts if you prefer.  
3. **caddy**: Listens on port 80/443, obtains a TLS cert for `CADDY_DOMAIN` via Let’s Encrypt, and reverse proxies requests to `appflowy:8080`.  
4. **db_backup**: A daily cron job at 2 AM that runs `pg_dump`, uploads to S3, and removes backups older than 7 days.

Check logs:

```bash
podman-compose logs -f
```

- **Caddy**: watch for successful SSL certificate issuance.  
- **db_backup**: the actual backup job logs appear after the daily cron runs (or you can manually trigger it inside the container).  

Once up, visit `https://your-domain` (the `CADDY_DOMAIN`) to access AppFlowy. You should see a valid TLS certificate and the AppFlowy interface.

---

## Automated Database Backups

### How It Works

1. The **db_backup** container is built from `backup/Dockerfile` (Alpine + Postgres client + AWS CLI).  
2. **`backup-cron.sh`** sets a cron job for **2:00 AM** daily, calling `backup.sh`.  
3. **`backup.sh`**:
   - Runs `pg_dump` on your Postgres database.  
   - Uploads the dump (`.sql`) to `s3://<S3_BUCKET_NAME>/backups/`.  
   - Lists objects under `backups/`, compares timestamps, and **deletes anything older than 7 days**.

> For large setups or production, many prefer to handle old file deletion with an **S3 Lifecycle Policy** (see below).

### S3 Cleanup

**By default**, the script parses `aws s3 ls` output, looking for backups older than 7 days, then deletes them. If you want to let S3 handle cleanup automatically:

1. Remove the “delete older than 7 days” logic in `backup.sh`.  
2. Set up an **S3 Lifecycle Policy** to expire objects under `/backups/` after 7 days.

### Restore a Backup

1. Download the desired `.sql` file from S3:
   ```bash
   aws s3 cp s3://your-s3-bucket-name/backups/appflowy_YYYY-MM-DD_HH-MM-SS.sql .
   ```
2. Use `psql` to restore it into your Postgres DB:
   ```bash
   psql -U appflowy -d appflowy -h <postgres_host> -f appflowy_YYYY-MM-DD_HH-MM-SS.sql
   ```

---

## Caddy for SSL/TLS

[Caddy](https://caddyserver.com/) automatically manages certificates via **Let’s Encrypt**. It listens on **ports 80** and **443**, so ensure:

- Your domain (`CADDY_DOMAIN`) has a valid DNS record pointing to the server.  
- Ports 80 and 443 are open on your firewall.  

The `Caddyfile` does a simple `reverse_proxy appflowy:8080`. If you need advanced configuration or custom headers, add them in `Caddyfile`.

---

## Advanced Tips

### Using S3 Lifecycle Policies

Instead of manually deleting older backups, you can:

- Remove the relevant lines in `backup.sh` that parse and delete older objects.  
- [Create an S3 Lifecycle Configuration](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html) to automatically expire objects after N days.

### Customizing the Backup Schedule

- Edit `backup-cron.sh` to change `0 2 * * *` (which is 2 AM daily).  
- For instance, `0 */6 * * *` would run every 6 hours, `30 1 * * *` runs at 1:30 AM daily, etc.

---

## Updating AppFlowy Source

If you’re using **Git submodules**:

```bash
cd appflowy/
git checkout main
git pull origin main
cd ..
git add appflowy
git commit -m "Update AppFlowy submodule to latest"
```

Then rebuild as needed (e.g., `./build_appflowy.sh`).

If you’re **cloning** in `build_appflowy.sh` with `--depth=1`, update that script to fetch the latest main branch.

---

## Contributing

- **Issues/PRs**: If you encounter issues or have improvements, feel free to open a PR or issue in this repo.  
- **AppFlowy Core**: For bugs or feature requests in the core AppFlowy code, contribute directly to the official [AppFlowy-IO/AppFlowy](https://github.com/AppFlowy-IO/AppFlowy) repo.  

---

## License

- This repository’s scripts/configuration are provided under your preferred open-source license (e.g., MIT).  
- AppFlowy itself is licensed under [AGPLv3](https://github.com/AppFlowy-IO/AppFlowy/blob/main/LICENSE).  
- The Docker/Podman images for **Postgres** and **Caddy** each have their own licenses.

> Use at your own risk. Always keep backups, secure your `.env` secrets, and test thoroughly before production deployment.
