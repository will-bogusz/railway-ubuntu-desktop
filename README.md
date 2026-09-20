# railway-ubuntu-desktop

Image behind the Railway template **Ubuntu Desktop (Browser)** (`railway.com/deploy/ubuntu-desktop`). Ubuntu 24.04 + XFCE served by KasmVNC 1.5.0 (browser-only web client) behind nginx basic auth on `$PORT`, Firefox from Mozilla's apt repo, `/home/dev` on a volume, `/healthz` open.

## Runtime contract

| variable | required | meaning |
|---|---|---|
| `PASSWORD` | yes | basic-auth password for user `dev` (the template generates it) |
| `PORT` | yes (8080) | nginx listen port; Railway's domain and healthcheck target it |
| `RESOLUTION` | no (`1440x900`) | Xvnc geometry `WIDTHxHEIGHT` |
| `TZ` | no | zoneinfo name |

Processes: `Xvnc :1` (loopback :6901, `-SecurityTypes None -DisableBasicAuth 1`, nginx is the gate), XFCE session as `dev`, `nginx` on `$PORT`. Exits when Xvnc or nginx dies. Measured: 135 MiB idle on Docker, 195 MiB idle on Railway; +400–700 MiB with Firefox.

## Build

GitHub Actions builds and pushes (**Actions → build → Run workflow**, tag default `24.04-YYYYMMDD`); the run summary prints `name:tag@sha256:…`. `build.sh` does the same on a docker host with a `write:packages` token. Bump the ARGs (`KASMVNC_VERSION`/`_SHA256`, `UBUNTU_DIGEST`), rebuild under a new tag, then update the template's image in Railway's editor.

## Local check

```bash
docker run --rm -p 8080:8080 --shm-size 512m -e PASSWORD=test -v desk-home:/home/dev ghcr.io/will-bogusz/railway-ubuntu-desktop:24.04-20260920
# open http://dev:test@localhost:8080/
```
