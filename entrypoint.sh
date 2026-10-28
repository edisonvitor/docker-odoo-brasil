#!/bin/bash

set -e


# Monta o addons_path
directories=$(ls -d -1 /mnt/addons/**)
path=","
for directory in $directories; do
  if [ -d $directory ]; then
    if [ $directory != "/mnt/addons/extra-addons" ]; then
      path="$path""$directory",
    fi
  fi
done

export ADDONS_PATH="$path"


# Gera o odoo.conf a partir do template a cada start
envsubst < /etc/odoo/odoo.conf.tpl > "$ODOO_RC"

# Canais do queue_job via env: uma seção [queue_job] no odoo.conf quebra o
# config.save() do Odoo (DuplicateSectionError ao criar banco pela tela)
export ODOO_QUEUE_JOB_CHANNELS="$QUEUE_JOB_CHANNELS"


if [ -v PASSWORD_FILE ]; then
    PASSWORD="$(< $PASSWORD_FILE)"
fi

# set the postgres database host, port, user and password according to the environment
# and pass them as arguments to the odoo process if not present in the config file
: ${HOST:=${DB_PORT_5432_TCP_ADDR:='db'}}
: ${PORT:=${DB_PORT_5432_TCP_PORT:=5432}}
: ${USER:=${DB_ENV_POSTGRES_USER:=${POSTGRES_USER:='odoo'}}}
: ${PASSWORD:=${DB_ENV_POSTGRES_PASSWORD:=${POSTGRES_PASSWORD:='odoo'}}}

# Para comandos que não recebem os --db_* (click-odoo-*, psql)
export PGHOST="$HOST" PGPORT="$PORT" PGUSER="$USER" PGPASSWORD="$PASSWORD"

DB_ARGS=()
function check_config() {
    param="$1"
    value="$2"
    if grep -q -E "^\s*\b${param}\b\s*=" "$ODOO_RC" ; then       
        value=$(grep -E "^\s*\b${param}\b\s*=" "$ODOO_RC" |cut -d " " -f3|sed 's/["\n\r]//g')
    fi;
    DB_ARGS+=("--${param}")
    DB_ARGS+=("${value}")
}

check_config "db_host" "$HOST"
check_config "db_port" "$PORT"
check_config "db_user" "$USER"
check_config "db_password" "$PASSWORD"

# Testa a conexão no banco configurado (o primeiro de DATABASE), não no "postgres"
WAIT_ARGS=("${DB_ARGS[@]}" --timeout=30)
if [[ -n "$DATABASE" && "$DATABASE" != "False" ]]; then
    WAIT_ARGS+=(--db_name "${DATABASE%%,*}")
fi

case "$1" in
    -- | odoo)
        shift
        if [[ "$1" == "scaffold" ]] ; then
            exec odoo "$@"
        else
            wait-for-psql.py "${WAIT_ARGS[@]}"
            exec odoo "$@" "${DB_ARGS[@]}"
        fi
        ;;
    -*)
        wait-for-psql.py "${WAIT_ARGS[@]}"
        exec odoo "$@" "${DB_ARGS[@]}"
        ;;
    *)
        exec "$@"
esac

exit 1
