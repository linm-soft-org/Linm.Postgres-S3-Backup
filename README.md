# Linm.Postgres-S3-Backup

Docker image that periodically backs up a PostgreSQL database to S3-compatible storage (AWS S3, Cloudflare R2, …) and supports restore on demand.

Maintained by [linm-soft-org](https://github.com/linm-soft-org). Fork lineage: [eeshugerman/postgres-backup-s3](https://github.com/eeshugerman/postgres-backup-s3) → [solectrus/postgres-s3-backup](https://github.com/solectrus/postgres-s3-backup).

---

## Install

### 1. Chọn image tag (Postgres major)

Image tag **phải khớp major version Postgres** bạn đang chạy (client `pg_dump` trong container theo version đó).

| Postgres server | Image tag |
|-----------------|-----------|
| 14.x | `14` |
| 15.x | `15` |
| 16.x | `16` |
| 17.x | `17` |
| 18.x | `18` |

Registry (GHCR):

```text
ghcr.io/linm-soft-org/linm.postgres-s3-backup:<tag>
```

Ví dụ Postgres 18:

```text
ghcr.io/linm-soft-org/linm.postgres-s3-backup:18
```

> GitHub Container Registry chuyển tên repo sang chữ thường trong đường dẫn image (`Linm.Postgres-S3-Backup` → `linm.postgres-s3-backup`).

### 2. Pull image

**Package public** — pull trực tiếp:

```sh
docker pull ghcr.io/linm-soft-org/linm.postgres-s3-backup:18
```

**Package private** — đăng nhập GHCR trước (PAT cần quyền `read:packages`):

```sh
echo "$GITHUB_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USER --password-stdin
docker pull ghcr.io/linm-soft-org/linm.postgres-s3-backup:18
```

Release git tag (`v1.0.0`, …) được tạo tự động khi merge vào `main`; **tag Docker vẫn là số Postgres major** (`14` … `18`), không phải semver.

### 3. Biến môi trường bắt buộc

| Biến | Mô tả |
|------|--------|
| `POSTGRES_HOST` | Host Postgres (vd. `postgres`, `postgres.railway.internal`) |
| `POSTGRES_PORT` | Cổng (mặc định `5432`) |
| `POSTGRES_DATABASE` | Tên database |
| `POSTGRES_USER` | User Postgres |
| `POSTGRES_PASSWORD` | Password Postgres |
| `S3_BUCKET` | Tên bucket S3 / R2 |
| `S3_ACCESS_KEY_ID` | Access key |
| `S3_SECRET_ACCESS_KEY` | Secret key |
| `S3_REGION` | Region AWS hoặc `auto` với **Cloudflare R2** |

Biến thường dùng thêm:

| Biến | Mặc định | Mô tả |
|------|----------|--------|
| `S3_PREFIX` | `backup` | Thư mục (folder) trên bucket — phần đầu của S3 key |
| `BACKUP_FILE_PREFIX` | *(empty)* | Tiền tố **tên file** backup (xem [Backup file naming](#backup-file-naming)) |
| `S3_ENDPOINT` | *(AWS)* | URL S3-compatible, vd. R2: `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` |
| `S3_S3V4` | `no` | Đặt `yes` nếu provider yêu cầu signature v4 |
| `SCHEDULE` | *(empty)* | Cron [go-cron](http://godoc.org/github.com/robfig/cron#hdr-Predefined_schedules); trống = backup **một lần** rồi thoát |
| `BACKUP_KEEP_DAYS` | *(empty)* | Xóa backup cũ trên S3 sau N ngày |
| `PASSPHRASE` | *(empty)* | Mã hóa GPG backup khi set |
| `PGDUMP_EXTRA_OPTS` | *(empty)* | Thêm flag cho `pg_dump` |

Template đầy đủ: [`template.env`](template.env).

### Backup file naming

Hai biến độc lập — **không nhầm** `S3_PREFIX` (folder trên bucket) với `BACKUP_FILE_PREFIX` (tiền tố tên file):

| Biến | Vai trò | Ví dụ |
|------|---------|--------|
| `S3_PREFIX` | Folder trên bucket | `production-backup` |
| `BACKUP_FILE_PREFIX` | Tiền tố tên file (tùy chọn) | `reva-prod` |
| `POSTGRES_DATABASE` | Tên DB trong tên file | `railway` |

**Pattern tên file** (timestamp UTC `YYYY-MM-DDTHH:MM:SS`):

```text
{S3_PREFIX}/{BACKUP_FILE_PREFIX}_{POSTGRES_DATABASE}_{timestamp}.dump
```

Nếu `BACKUP_FILE_PREFIX` trống → bỏ phần tiền tố + dấu `_` thừa:

```text
{S3_PREFIX}/{POSTGRES_DATABASE}_{timestamp}.dump
```

**Ví dụ** — bucket `linm-prod-backup`, `S3_PREFIX=production-backup`, `BACKUP_FILE_PREFIX=reva-prod`, `POSTGRES_DATABASE=railway`:

```text
s3://linm-prod-backup/production-backup/reva-prod_railway_2026-07-09T05:00:00.dump
```

Mã hóa GPG (`PASSPHRASE` set) → thêm hậu tố `.gpg`.

**Restore:**

```sh
# Latest backup (tìm theo S3_PREFIX + BACKUP_FILE_PREFIX + POSTGRES_DATABASE)
docker exec <container> sh restore.sh

# Backup cụ thể — chỉ truyền phần timestamp (không gồm prefix/folder)
docker exec <container> sh restore.sh 2026-07-09T05:00:00
```

**R2 lifecycle:** rule prefix nên khớp `S3_PREFIX/` (vd. `production-backup/`).

### 4. Chạy với Docker Compose (local / dev)

Trong repo này:

```sh
cp template.env .env
# Sửa .env: S3_*, POSTGRES_*, SCHEDULE, …
docker compose up -d --build
```

`docker-compose.yaml` build image từ `Dockerfile` với `POSTGRES_VERSION=18` và service `postgres` mẫu — phù hợp dev, không dùng image GHCR.

Production: trỏ service `backup` sang image GHCR thay vì `build:` (xem mục Usage).

### 5. Chạy standalone (`docker run`)

```sh
docker run -d --name postgres-s3-backup \
  -e POSTGRES_HOST=postgres \
  -e POSTGRES_PORT=5432 \
  -e POSTGRES_DATABASE=mydb \
  -e POSTGRES_USER=user \
  -e POSTGRES_PASSWORD=secret \
  -e S3_BUCKET=my-bucket \
  -e S3_REGION=auto \
  -e S3_ENDPOINT=https://ACCOUNT_ID.r2.cloudflarestorage.com \
  -e S3_ACCESS_KEY_ID=... \
  -e S3_SECRET_ACCESS_KEY=... \
  -e S3_PREFIX=backup/ \
  -e BACKUP_FILE_PREFIX=reva-prod \
  -e SCHEDULE='0 5,17 * * *' \
  ghcr.io/linm-soft-org/linm.postgres-s3-backup:18
```

- **Volume (khuyến nghị production):** mount `/tmp` — image ghi lock + healthcheck tại `/tmp` (`backup.lock`, `last_backup_success`). Railway / platform có disk nhỏ nên gắn volume tại `/tmp`.
- **Network:** container backup phải reach được Postgres (cùng Docker network hoặc private network như Railway internal).

### 6. Railway + Cloudflare R2 (production Linm)

1. **+ New** → **Empty Service** → Deploy from Docker image  
   `ghcr.io/linm-soft-org/linm.postgres-s3-backup:18`
2. **Volume:** mount path `/tmp`
3. **Variables** — Postgres nội bộ Railway + R2:

| Key | Gợi ý (Railway + R2) |
|-----|----------------------|
| `POSTGRES_HOST` | `postgres.railway.internal` |
| `POSTGRES_DATABASE` | `railway` |
| `POSTGRES_USER` | `postgres` |
| `POSTGRES_PASSWORD` | `${{Postgres.PGPASSWORD}}` hoặc copy từ service Postgres |
| `S3_REGION` | `auto` |
| `S3_ENDPOINT` | `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` |
| `S3_BUCKET` | tên bucket R2 |
| `S3_PREFIX` | vd. `production-backup/` |
| `BACKUP_FILE_PREFIX` | *(tùy chọn)* vd. `reva-prod` |
| `SCHEDULE` | `0 5,17 * * *` (12:00 & 00:00 ICT) |

Không public port. Sau deploy: **Restart** một lần để xem log backup; kiểm tra object trên R2 under `S3_PREFIX`.

Chi tiết R2 lifecycle, troubleshooting: [postgres-r2-backup-railway-setup](https://github.com/linm-soft-org/Linm.Development.Rules/blob/main/docs/danh-gia-he-thong/postgres-r2-backup-railway-setup.md) (repo Rules).

---

## Usage

### Docker Compose (image GHCR)

```yaml
services:
  postgres:
    image: postgres:18-alpine
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password

  backup:
    image: ghcr.io/linm-soft-org/linm.postgres-s3-backup:18
    environment:
      SCHEDULE: '@weekly' # optional
      BACKUP_KEEP_DAYS: 7 # optional
      PASSPHRASE: passphrase # optional
      S3_REGION: auto
      S3_ENDPOINT: https://ACCOUNT_ID.r2.cloudflarestorage.com
      S3_ACCESS_KEY_ID: key
      S3_SECRET_ACCESS_KEY: secret
      S3_BUCKET: my-bucket
      S3_PREFIX: backup
      BACKUP_FILE_PREFIX: reva-prod # optional
      POSTGRES_HOST: postgres
      POSTGRES_DATABASE: postgres
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
    depends_on:
      - postgres
```

- Tag image = **major Postgres** (`14` … `18`).
- `SCHEDULE`: cron go-cron; bỏ trống → backup ngay một lần rồi exit.
- `PASSPHRASE`: mã hóa GPG file dump.
- Backup ad-hoc: `docker exec <container> sh backup.sh`
- `BACKUP_KEEP_DAYS`: xóa object S3 cũ (pagination đầy đủ).
- `S3_PATH`: deprecated; dùng `S3_PREFIX`.
- `BACKUP_FILE_PREFIX`: tiền tố tên file; restore/list tự khớp — xem [Backup file naming](#backup-file-naming).
- Sau upload: so sánh size local vs remote; lock file chống backup song song.
- Production: ưu tiên secrets / mounted files thay vì plain env cho credential.

## Restore

> [!CAUTION]
> DATA LOSS! All database objects will be dropped and re-created.

### ... from latest backup

```sh
docker exec <container name> sh restore.sh
```

### ... from specific backup

```sh
docker exec <container name> sh restore.sh <timestamp>
```

---

## Development

### Build image locally

`POSTGRES_VERSION` = major Postgres (14–18):

```sh
DOCKER_BUILDKIT=1 docker build --build-arg POSTGRES_VERSION=18 .
```

### Test stack (Compose build from source)

```sh
cp template.env .env
# fill out secrets in .env
docker compose up -d --build --force-recreate
```

---

## CI / Publish

| Workflow | Khi chạy |
|----------|----------|
| `CI` | PR / push `dev` — build verify Postgres 18 |
| `Publish Docker images` | Push `main` — push matrix `14`–`18` lên GHCR + git tag `vX.Y.Z` |

---

## Acknowledgements

Fork of @eeshugerman's [postgres-backup-s3](https://github.com/eeshugerman/postgres-backup-s3), with PostgreSQL 17+ support from [solectrus/postgres-s3-backup](https://github.com/solectrus/postgres-s3-backup).

Original lineage: @schickling's [postgres-backup-s3](https://github.com/schickling/dockerfiles/tree/master/postgres-backup-s3) and [postgres-restore-s3](https://github.com/schickling/dockerfiles/tree/master/postgres-restore-s3).
