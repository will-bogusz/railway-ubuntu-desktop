# railway-ubuntu-desktop

Image behind the Railway template **Ubuntu Desktop (Browser)** (`railway.com/deploy/ubuntu-desktop`). Ubuntu 24.04 + XFCE served by KasmVNC 1.5.0 (browser-only web client) behind nginx basic auth on `$PORT`, Firefox from Mozilla's apt repo, `/home/dev` on a volume, `/healthz` open.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/ubuntu-desktop?referralCode=MYUCwz)

## Runtime contract

| variable | required | meaning |
|---|---|---|
| `PASSWORD` | yes | basic-auth password for user `dev` (the template generates it) |
| `PORT` | yes (8080) | nginx listen port; Railway's domain and healthcheck target it |
| `RESOLUTION` | no (`1440x900`) | Xvnc geometry `WIDTHxHEIGHT` |
| `TZ` | no | zoneinfo name |

Processes: `Xvnc :1` (loopback :6901, `-SecurityTypes None -DisableBasicAuth 1`, nginx is the gate), XFCE session as `dev`, `nginx` on `$PORT`. Each runs under a respawn loop: XFCE *Log Out* starts a fresh session, and a killed process is restarted in-container; the container stops only on SIGTERM (bounded: TERM, 1 s, KILL, exit 0). `RESOLUTION` tolerates `1920X1080`/spaces and falls back to 1440x900 when unparseable. Measured: 135 MiB idle on Docker, 166–195 MiB idle on Railway; Firefox adds ~300–600 MiB, so on Free (0.5 GB) Firefox is OOM-killed at launch (the desktop stays up) and Trial (1 GB) fits a few tabs.

`desktop-oomadj` (`oomadj.sh`, also under a respawn loop) resets any negative `oom_score_adj` above -1000 to 0 four times a second. Railway starts `railway ssh` sessions (the dashboard's SSH button) at -950, so a memory hog run there made the kernel kill Xvnc, XFCE, nginx and the entrypoint instead of the hog: the container exited as `crashed` + `oom_killed`, and after ten such exits the deployment stayed CRASHED (measured at 0.5 GB, 2026-10-18). With every process at 0 the kernel kills the hog and the desktop stays up.

The loop alone lost a race: a hog forked from a -950 shell that allocated within the 0.25 s window still crashed the container. `/usr/local/lib/liboomguard.so` (`oomguard.c`, listed in `/etc/ld.so.preload`) closes it by resetting every dynamically linked program to 0 at exec, before `main`; the loop stays as the backstop for static binaries and processes already running.

## Build

GitHub Actions builds and pushes (**Actions → build → Run workflow**, tag default `24.04-YYYYMMDD`); the run summary prints `name:tag@sha256:…`. `build.sh` does the same on a docker host with a `write:packages` token. Bump the ARGs (`KASMVNC_VERSION`/`_SHA256`, `UBUNTU_DIGEST`), rebuild under a new tag, then update the template's image in Railway's editor.

## Local check

```bash
docker run --rm -p 8080:8080 --shm-size 512m -e PASSWORD=test -v desk-home:/home/dev ghcr.io/will-bogusz/railway-ubuntu-desktop:24.04-20260920
# open http://dev:test@localhost:8080/
```
