# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Docker image for **Odoo 18.0** with Brazilian localization from **OCA l10n-brazil** (published as `craines/odoo-brasil:18.0`). The repo has no application code of its own. It holds the image build (`Dockerfile`, `entrypoint.sh`, `odoo.conf.tpl`, `wait-for-psql.py`, `br_requirements.txt`). `addons/` is empty and is meant for custom modules. Docs and commit messages are in Portuguese.

Before 18.0, the image was Odoo 15 with Trust-Code `odoo-brasil`/`trustcode-addons` and code-137. Those projects are abandoned and were dropped, so there is no data migration path from old 15.0 databases.

## Commands

```bash
docker build -t craines/odoo-brasil:18.0 .     # args: ODOO_TAG (official image tag), ADDONS_BRANCH
docker compose up -d                           # builds the image, Postgres 16, named volumes, ./addons mounted as extra-addons
# install modules / smoke test (fails fast if an OCA dependency repo is missing)
docker compose run --rm -e LOG_FILE=False -e WORKERS=0 odoo odoo -d teste -i l10n_br_base,l10n_br_nfe --stop-after-init --without-demo=all
```

There is no lint or test setup. Logs go to stdout by default (`LOG_FILE=False`); set `LOG_FILE` to a path to log to a file instead.

`docker-compose.yml` is for local development only (fixed `odoo`/`odoo` credentials). `docker-compose.prod.yml` puts Caddy (automatic HTTPS, `Caddyfile`) in front of Odoo, exposes no Odoo/Postgres ports, and reads config from `.env` (template: `.env.example`). It uses `env_file` rather than `${VAR}` interpolation because the image's generic names (`USER`, `HOST`, `PASSWORD`) would be overridden by the shell's own variables. The repo is public: never commit `.env` or real credentials.

## How the image fits together

- **Multi-stage build**: the `alpine/git` stage shallow-clones every addon repo (OCA repos plus `odoo/design-themes`) into `/addons/<repo>`, deletes each `.git`, and concatenates every repo's `requirements.txt` into `oca_requirements.txt`. The final stage is the official `odoo:<ODOO_TAG>` image (Ubuntu noble, Python 3.12). It pip-installs `oca_requirements.txt` plus `br_requirements.txt` with `--break-system-packages`. Build deps are added and purged inside the same `RUN`.
- **Adding an addon repo**: add it to the `for repo in` list in the Dockerfile. The repo must have an `18.0` branch. Its Python requirements get picked up automatically. To decide which repos are needed, take the `depends` of the `l10n_br_*` manifests and find the OCA repo for each one. Some dependencies (`account_fleet`, `account_qr_code_emv`, `certificate`) are Odoo core modules.
- `br_requirements.txt` holds only extras (`click-odoo-contrib`, `sentry-sdk`) and the pins l10n-brazil relies on (`signxml==3.2.2`, `requests_pkcs12<1.23`). Don't upgrade `cryptography` with pip: pyOpenSSL from the base image depends on the apt version.

## Runtime configuration (entrypoint.sh)

1. Builds `ADDONS_PATH` from every directory in `/mnt/addons/*` except `extra-addons`. The template puts `extra-addons` first, so local modules take precedence.
2. Renders `/etc/odoo/odoo.conf.tpl` through `envsubst` into `$ODOO_RC` (`/etc/odoo/odoo.conf`) on every start. The `ENV` defaults in the Dockerfile fill the placeholders, and the full list is in `Readme.md`.
3. Exports `HOST`/`PORT`/`USER`/`PASSWORD` as `PGHOST`/`PGPORT`/`PGUSER`/`PGPASSWORD` (so `click-odoo-*` and `psql` work) and never prints them. Also passes them (or `PASSWORD_FILE`) as `--db_*` args, waits for Postgres with `wait-for-psql.py` (30s), then `exec`s `odoo`. `odoo scaffold` skips the wait, and any other command is exec'd as-is.

`queue_job` is in `server_wide_modules` and needs `WORKERS > 0`. Its channels come from `QUEUE_JOB_CHANNELS`. To expose a new Odoo option, add a `key = $VAR` line to `odoo.conf.tpl` and an `ENV VAR=default` to the Dockerfile, and document it in `Readme.md`.
