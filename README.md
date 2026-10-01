# mega-facecompare-fe

| Metadata | |
|---|---|
| Judul | README mega-facecompare-fe (compreface-fe) |
| Versi | 2.0.0 |
| Tanggal | 2026-10-01 |
| Owner | Tim Platform / DevOps |
| Status | Review |

| Versi | Tanggal | Penulis | Perubahan |
|---|---|---|---|
| 1.0.0 | 2026-09-29 | Claude Code | Versi awal (di monorepo `services/<service>/README.md`) |
| 2.0.0 | 2026-10-01 | Claude Code | Repo mandiri hasil split monorepo Mega-CompreFace |

**Frontend (UI) + reverse proxy** — image `mega/compreface-fe`. Bagian dari CompreFace (fork Exadel CompreFace 1.2.0, Apache 2.0) yang dipecah
dari monorepo Mega-CompreFace menjadi 6 repo. Integrasi full-stack, monitoring, dokumentasi SDLC (SPEC,
ARCHITECTURE, RUNBOOK, SECURITY, TEST_PLAN) dan versi rilis bersama ada di
[mega-facecompare-deploy](https://scm.bankmegadev.com/cobs/data-management/application/mega-facecompare-deploy).

## Fungsi
UI admin CompreFace (Angular 11, source `ui/`) disajikan oleh nginx, sekaligus reverse proxy ke admin (`/admin/**`) dan api (`/api/v1/**`, swagger) serta `GET /core/status` ke core (dipakai UI). Satu-satunya service yang diekspos ke luar (lewat ingress).

Source aplikasi: `ui/` (Angular, upstream Exadel + rebrand Bank Mega). **Logika aplikasi upstream tidak diubah** di repo ini; perubahan hanya pada
build, konfigurasi, dan dokumentasi.

## Isi repo
| File | Isi |
|---|---|
| `Dockerfile` | Stage 1 `node:12.22.12` → `npm run build:prod`; stage 2 `nginxinc/nginx-unprivileged:1.21.1` (uid 101) |
| `.dockerignore` | Context hanya `ui/` (tanpa `node_modules`/`dist`/`e2e`), `docker/`, `LICENSE`, `NOTICE` |
| `docker/nginx.conf` | Konfigurasi utama (pid/temp di `/tmp`, log akses JSON tanpa query string) |
| `docker/nginx.conf.template` | Server block: resolver dinamis, upstream dari env, hanya `GET /core/status` ke core, `/healthz` |
| `docker/docker-entrypoint-fe.sh` | Deteksi resolver dari resolv.conf + auto-FQDN, lalu entrypoint nginx resmi (envsubst) |
| `scripts/build.sh` | Build `mega/compreface-fe:<versi>` dari root repo (versi default: file `VERSION`); tulis `build/images.txt` |
| `scripts/push.sh` | Push ke registry (catat digest ke `build/digests.txt`) atau `--save <dir>` → tarball + `SHA256SUMS` untuk transfer air-gapped |
| `k8s/base/` | Manifest service ini saja (Deployment/StatefulSet, Service, ConfigMap, NetworkPolicy) |
| `k8s/overlays/{dev,prod}/` | Overlay per environment untuk service ini |
| `.gitlab-ci.yml` | validate → build → scan (Trivy) → push; registry & kredensial dari variabel CI |
| `.env.example` | Env var service ini (tanpa nilai rahasia) |

## Port & healthcheck
| Port | Healthcheck | Catatan |
|---|---|---|
| 8080 (Service k8s: 80) | `GET /healthz` → `ok` | Hanya mengecek nginx; fe tetap healthy walau admin/api down (502) |

## Env var
Non-rahasia (ConfigMap `compreface-fe`, default juga di-bake di `Dockerfile`/`.env.example`):

| Variabel | Default | Catatan |
|---|---|---|
| `ADMIN_UPSTREAM` | `compreface-admin:8080` | host:port admin (tanpa skema) |
| `API_UPSTREAM` | `compreface-api:8080` | host:port api |
| `CORE_UPSTREAM` | `compreface-core:3000` | host:port core (hanya untuk `GET /core/status`) |
| `NGINX_RESOLVER` | (kosong) | kosong = otomatis dari `/etc/resolv.conf` |
| `NGINX_RESOLVER_VALID` | `10s` | TTL cache DNS nginx |
| `NGINX_UPSTREAM_AUTO_FQDN` | `true` | lengkapi nama pendek dengan domain search pertama (k8s) |
| `CLIENT_MAX_BODY_SIZE` | `10M` | batas upload |
| `PROXY_READ_TIMEOUT` | `60000ms` |  |
| `PROXY_CONNECT_TIMEOUT` | `10000ms` |  |
| `TZ` | `Asia/Jakarta` |  |

Referensi lengkap seluruh service: `docs/CONFIGURATION.md` di repo deploy.

## Build
```bash
scripts/build.sh                       # → mega/compreface-fe:$(cat VERSION)
REGISTRY=registry.example.internal scripts/build.sh && scripts/push.sh
scripts/push.sh --save /media/transfer # air-gapped: docker save + SHA256SUMS → docker load di sisi internal
# manual (build context = root repo, tanpa akses ke repo lain):
docker build -t mega/compreface-fe:1.2.0 .
```
Tag `latest` ditolak. Versi image dinaikkan dengan mengubah `VERSION` + `CHANGELOG.md`; versi yang dirilis
bersama dicatat di `versions.env` repo deploy.

## Run (lokal, tanpa orkestrasi)
```bash
cp .env.example .env    # isi nilai yang ditandai WAJIB
docker run -d --name compreface-fe -p 8000:8080 --read-only \
  --tmpfs /tmp --tmpfs /etc/nginx/conf.d:mode=1777 \
  -e ADMIN_UPSTREAM=compreface-admin:8080 -e API_UPSTREAM=compreface-api:8080 \
  -e CORE_UPSTREAM=compreface-core:3000 \
  --network <network-yang-berisi-admin-api-core> mega/compreface-fe:1.2.0
curl -fsS http://127.0.0.1:8000/healthz
```
Untuk full-stack (5 service) gunakan `scripts/compose.sh` di repo deploy.

## Kubernetes
```bash
kubectl kustomize k8s/overlays/dev          # render
kubectl apply -k k8s/overlays/dev           # namespace compreface-dev harus sudah ada (dibuat repo deploy)
```
Namespace, NetworkPolicy default-deny + DNS egress, dan Secret dikelola di repo deploy. Repo deploy menyimpan
salinan `k8s/base/` repo ini di `k8s/services/compreface-fe/` — setelah mengubah `k8s/base/`, jalankan
`scripts/sync-manifests.sh` di repo deploy.

## Kontrak ke service lain
Nama Service, port dan nama env var **tidak berubah** dibanding monorepo — perubahannya adalah breaking change
dan harus dikoordinasikan lewat repo deploy.

- **Memanggil**: `compreface-admin:8080` (`/admin/**`), `compreface-api:8080` (`/api/v1/**`, `/swagger-ui.html`, `/v2/api-docs`), `compreface-core:3000` (hanya `GET /core/status`). Alamat diambil dari env `ADMIN_UPSTREAM`/`API_UPSTREAM`/`CORE_UPSTREAM` (ConfigMap `compreface-fe`) — **tidak ada hostname hardcode** di image.
- **Dipanggil oleh**: ingress / pengguna (browser) dan klien REST API (lewat `/api/v1`).
- NetworkPolicy `compreface-fe`: ingress dari mana saja ke :8080; egress hanya ke admin/api :8080 dan core :3000.

## Catatan operasional
Butuh `/tmp` dan `/etc/nginx/conf.d` writable (emptyDir/tmpfs) bila root FS read-only. Overlay prod menyertakan contoh Ingress (`k8s/overlays/prod/ingress.example.yaml`, nonaktif).

## Lisensi
Apache License 2.0 — lihat [LICENSE](LICENSE) dan [NOTICE](NOTICE) (atribusi Exadel, Inc. dipertahankan).
