# Odoo 18 with Brazilian localization (OCA) on Docker

[Português](Readme.md) | **English**

A Docker image of **Odoo 18.0 Community** with the Brazilian localization from [OCA l10n-brazil](https://github.com/OCA/l10n-brazil) (NF-e, NFS-e, CT-e, MDF-e, tax engine, accounting, boletos/CNAB) and the OCA repositories it depends on.

The image is built on the official [`odoo:18.0`](https://hub.docker.com/_/odoo) image (Ubuntu Noble, Python 3.12). The addons are fetched while the image is built, without `.git`. The [`addons/`](addons/) folder is for your own modules.

Included repositories (branch `18.0`):

`OCA/l10n-brazil`, `web`, `server-ux`, `reporting-engine`, `account-reconcile`, `account-financial-reporting`, `account-financial-tools`, `account-payment`, `account-invoicing`, `bank-payment`, `mis-builder`, `commission`, `currency`, `delivery-carrier`, `hr`, `product-attribute`, `brand`, `purchase-workflow`, `sale-workflow`, `queue` and `odoo/design-themes`.

## Development

```bash
docker compose up -d
```

[docker-compose.yml](docker-compose.yml) builds the image and starts Postgres 16. Odoo runs at http://localhost:8069. The `./addons` folder is mounted as `extra-addons`. It comes first in `addons_path`, so a module of yours overrides an OCA module with the same name.

The database user and password are `odoo`/`odoo`, and the master password is `admin`. Use this compose file on your own machine only.

To create a database and install the Brazilian modules:

```bash
docker compose run --rm -e WORKERS=0 odoo odoo -d mydb \
    -i l10n_br_base,l10n_br_fiscal,l10n_br_account,l10n_br_nfe,l10n_br_nfse,l10n_br_sale,l10n_br_purchase,l10n_br_coa_generic \
    --stop-after-init --without-demo=all
```

If the repository of a dependency is missing, the command fails right at the start. That also makes it a good smoke test for the image.

## Production

[docker-compose.prod.yml](docker-compose.prod.yml) runs three services:

- **Caddy**: reverse proxy with automatic HTTPS (Let's Encrypt). It is the only service that exposes ports (80 and 443).
- **Odoo**: configured through `.env` and reachable only on the compose internal network.
- **Postgres 16**: no exposed port, with a healthcheck.

Logs go to stdout (`docker compose logs`) and are rotated at 5 files of 50 MB.

### Prerequisites

- A domain with DNS pointing to the server.
- Ports 80 and 443 open.

### Starting

```bash
cp .env.example .env
# edit .env: DOMAIN, passwords (openssl rand -base64 32), DATABASE, SMTP...

# create the database and install the modules (once)
docker compose -f docker-compose.prod.yml run --rm -e WORKERS=0 odoo odoo -d producao \
    -i l10n_br_base,l10n_br_account,l10n_br_coa_generic \
    --stop-after-init --without-demo=all

docker compose -f docker-compose.prod.yml up -d
```

The value of `-d` must match `DATABASE` in `.env`. The first login uses user `admin` and password `admin`. **Change that password on first login.**

`.env.example` ships with `LIST_DB=False`, which turns off the database manager (`/web/database/manager`). Keep it that way on the internet. With it on, anyone who learns the master password can download or delete the databases.

### With an existing Postgres

[docker-compose.external-db.yml](docker-compose.external-db.yml) runs only Caddy and Odoo. The connection comes from `HOST`, `PORT`, `USER` and `PASSWORD` in `.env` (the "Postgres externo" section of `.env.example`). If Postgres runs on the same machine, outside Docker, use `HOST=host.docker.internal`.

On Postgres, as a superuser:

```sql
CREATE ROLE odoo LOGIN PASSWORD 'strong-password';
CREATE DATABASE producao OWNER odoo ENCODING 'UTF8'
    LC_COLLATE 'C' LC_CTYPE 'C.UTF-8' TEMPLATE template0;
-- connected to the producao database:
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

In `pg_hba.conf`, allow the user on the Odoo database **and on the `postgres` database**. On startup, Odoo connects to `postgres` to check whether its database exists, and it crashes if the connection is refused. The user still can't create databases.

```
host    producao    odoo    ODOO_IP/32    scram-sha-256
host    postgres    odoo    ODOO_IP/32    scram-sha-256
```

With a shared Postgres, tune `DB_MAXCONN` so that `(WORKERS + 2) × DB_MAXCONN` fits in the available `max_connections`.

```bash
docker compose -f docker-compose.external-db.yml run --rm -e WORKERS=0 odoo odoo -d producao \
    -i l10n_br_base,l10n_br_account,l10n_br_coa_generic --stop-after-init --without-demo=all
docker compose -f docker-compose.external-db.yml up -d
```

### Why `env_file` and not `${VAR}`

The image uses generic variable names (`USER`, `HOST`, `PORT`, `PASSWORD`). In compose `${VAR}` interpolation, shell variables take precedence over `.env`, so `${USER}` would become your Linux username. With `env_file: .env`, the values go straight into the container.

If you'd rather not keep the database password in a variable, set `PASSWORD_FILE` to a file, for example a Docker secret.

### Published image and pinned versions

[GitHub Actions](.github/workflows/build.yml) builds the image and publishes it to [`ghcr.io/edisonvitor/odoo-brasil`](https://github.com/edisonvitor/docker-odoo-brasil/pkgs/container/odoo-brasil). This happens on every push to `main`, every Monday (to pick up OCA fixes) and when the workflow is run by hand. Before publishing, the workflow installs the main modules on a throwaway Postgres. If a dependency is missing, the image isn't published.

| Tag | Use |
|---|---|
| `18.0` | Latest build |
| `18.0-YYYYMMDD` | Pinned, for production |
| `sha-<commit>` | Traces which commit the image came from |

The build clones the tip of the `18.0` branch of each OCA repository, so builds on different days produce different images. In production, use a dated tag in `ODOO_IMAGE` and test it on staging before switching. To roll back, point it at the previous tag again.

### Updating modules

After switching `ODOO_IMAGE` to a new version, pull the image and update the modules that changed:

```bash
docker compose -f docker-compose.prod.yml pull odoo
docker compose -f docker-compose.prod.yml run --rm -e WORKERS=0 odoo \
    click-odoo-update -c /etc/odoo/odoo.conf -d producao
```

Take a backup before updating.

### Backup

A backup has two parts: the database and the filestore, which holds attachments, NF-e XMLs and certificates.

```bash
mkdir -p backups
docker compose -f docker-compose.prod.yml exec -T db \
    sh -c 'pg_dump -U "$POSTGRES_USER" -Fc producao' > backups/producao-$(date +%F).dump
docker compose -f docker-compose.prod.yml exec -T odoo \
    tar czf - -C /var/lib/odoo/filestore producao > backups/filestore-$(date +%F).tar.gz
```

Schedule these commands (cron) and keep the copies **off the server**.

## Environment variables

`entrypoint.sh` renders `/etc/odoo/odoo.conf` from [odoo.conf.tpl](odoo.conf.tpl) on every start. To change the configuration, change the variable and restart the container.

| Variable | Default | Description |
|---|---|---|
| `HOST` | `localhost` | Postgres host |
| `PORT` | `5432` | Postgres port |
| `USER` | `odoo` | Postgres user |
| `PASSWORD` | `odoo` | Postgres password |
| `PASSWORD_FILE` | — | File with the Postgres password. Takes precedence over `PASSWORD`. |
| `ODOO_PASSWORD` | `admin` | Master password (`admin_passwd`). **Change it in production.** |
| `DATABASE` | `False` | Default database (`db_name`) |
| `DB_FILTER` | `False` | Regex of visible databases (`dbfilter`) |
| `LIST_DB` | `True` | Database manager. Use `False` in production. |
| `DB_MAXCONN` | `64` | Postgres connections per Odoo process (`db_maxconn`) |
| `WORKERS` | `5` | HTTP processes. Must be greater than 0 because of `queue_job`. |
| `QUEUE_JOB_CHANNELS` | `root:2` | `queue_job` channels |
| `LIMIT_MEMORY_SOFT` | `2147483648` | Memory per worker before it is recycled (bytes) |
| `LIMIT_MEMORY_HARD` | `2684354560` | Maximum memory per worker (bytes) |
| `TIME_CPU` | `6000` | `limit_time_cpu` (s) |
| `TIME_REAL` | `7200` | `limit_time_real` (s) |
| `ODOO_PORT` | `8069` | HTTP port |
| `LONGPOLLING_PORT` | `8072` | `gevent_port` (websocket) |
| `LOG_FILE` | `False` | `False` sends the log to stdout. Also accepts a path, for example `/var/lib/odoo/odoo.log`. |
| `DEBUG_MODE` | `False` | `debug_mode` |
| `EMAIL_FROM` | `odoo@teste.com` | Default sender |
| `SMTP_SERVER` | `localhost` | SMTP server |
| `SMTP_PORT` | `25` | SMTP port |
| `SMTP_SSL` | `False` | SMTP over SSL |
| `SMTP_USER` | `False` | SMTP user |
| `SMTP_PASSWORD` | `False` | SMTP password |

`queue_job`, which l10n-brazil uses, is already in `server_wide_modules`.

## Build

```bash
docker build -t craines/odoo-brasil:18.0 .
docker build --build-arg ODOO_TAG=18.0-20261015 --build-arg ADDONS_BRANCH=18.0 -t craines/odoo-brasil:18.0 .
```

- `ODOO_TAG` is the tag of the official `odoo` image.
- `ADDONS_BRANCH` is the branch cloned from the OCA repositories.

To add another OCA repository, add it to the `for repo in` list in the [Dockerfile](Dockerfile). It must have an `18.0` branch, and its `requirements.txt` is installed automatically.

## Useful modules

All of them are already in the image. Since they aren't flagged as "applications", they don't show up in the **Apps** screen with the default filter. To find them, turn on developer mode, click *Update Apps List*, remove the "Apps" filter and search by technical name.

| For | Modules |
|---|---|
| Chart of accounts | `l10n_br_coa_simple` (small businesses, ITG 1000) or `l10n_br_coa_generic` (standard tax regime) |
| Brazilian invoicing | `l10n_br_account`, `account_usability` (shows the accounting menus) |
| Payables/receivables | `l10n_br_account_due_list`, `l10n_br_account_payment_order` |
| Boletos and CNAB | `l10n_br_account_payment_brcobranca` (needs the [boleto_cnab_api](https://github.com/akretion/boleto_cnab_api) service), `l10n_br_cnab_structure` |
| Bank reconciliation | `account_reconcile_oca` |
| Reports | `l10n_br_mis_report` (balance sheet and income statement), `mis_builder_cash_flow`, `account_financial_report` |
| Tax documents | `l10n_br_nfe`, `l10n_br_nfse` |
| User interface | `web_responsive`, `web_dark_mode` |

## History

Up to version 15.0, this image used Trust-Code's `odoo-brasil`/`trustcode-addons` and code-137. Those projects were abandoned and dropped from the image. **There is no migration path** from 15.0 databases using those modules to this version.

## License

[AGPL-3.0](LICENSE). The modules bundled in the image keep their own licenses: AGPL-3 or LGPL-3 for OCA modules and LGPL-3 for Odoo.
