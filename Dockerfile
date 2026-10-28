ARG ODOO_TAG=18.0-20261015

# Stage 1: baixa os addons de terceiros (sem .git) para não carregar git na imagem final
FROM alpine/git:latest AS addons
ARG ADDONS_BRANCH=18.0
RUN set -eux; \
    mkdir /addons; \
    for repo in \
        OCA/l10n-brazil \
        OCA/web \
        OCA/server-ux \
        OCA/reporting-engine \
        OCA/account-reconcile \
        OCA/account-financial-reporting \
        OCA/account-financial-tools \
        OCA/account-payment \
        OCA/account-invoicing \
        OCA/bank-payment \
        OCA/mis-builder \
        OCA/commission \
        OCA/currency \
        OCA/delivery-carrier \
        OCA/hr \
        OCA/product-attribute \
        OCA/brand \
        OCA/purchase-workflow \
        OCA/sale-workflow \
        OCA/queue \
        odoo/design-themes \
    ; do \
        git clone -q --depth 1 --branch "${ADDONS_BRANCH}" "https://github.com/${repo}.git" "/addons/${repo#*/}"; \
        rm -rf "/addons/${repo#*/}/.git"; \
    done; \
    cat /addons/*/requirements.txt > /addons/oca_requirements.txt

# Stage 2: imagem oficial do Odoo (já traz wkhtmltopdf, postgresql-client, rtlcss e deps do Odoo)
FROM odoo:${ODOO_TAG}
USER root

COPY br_requirements.txt /tmp/br_requirements.txt
COPY --from=addons /addons/oca_requirements.txt /tmp/oca_requirements.txt

# Dependências de build ficam só durante o pip install
RUN set -eux; \
    buildDeps="build-essential python3-dev libxml2-dev libxmlsec1-dev pkg-config"; \
    apt-get update; \
    apt-get install -y --no-install-recommends gettext-base libxmlsec1-openssl $buildDeps; \
    pip install --no-cache-dir --break-system-packages \
        -r /tmp/oca_requirements.txt -r /tmp/br_requirements.txt; \
    apt-get purge -y --auto-remove $buildDeps; \
    rm -rf /var/lib/apt/lists/* /tmp/*_requirements.txt

COPY --from=addons --chown=odoo /addons /mnt/addons
COPY --chown=odoo addons /mnt/addons/extra-addons

ENV ODOO_PASSWORD=admin \
    HOST=localhost \
    PORT=5432 \
    USER=odoo \
    PASSWORD=odoo \
    DATABASE=False \
    DEBUG_MODE=False \
    LIST_DB=True \
    EMAIL_FROM=odoo@teste.com \
    SMTP_PASSWORD=False \
    SMTP_PORT=25 \
    SMTP_SERVER=localhost \
    SMTP_SSL=False \
    SMTP_USER=False \
    ODOO_PORT=8069 \
    WORKERS=5 \
    LOG_FILE=False \
    LONGPOLLING_PORT=8072 \
    TIME_CPU=6000 \
    TIME_REAL=7200 \
    LIMIT_MEMORY_SOFT=2147483648 \
    LIMIT_MEMORY_HARD=2684354560 \
    DB_FILTER=False \
    QUEUE_JOB_CHANNELS=root:2

COPY --chown=odoo odoo.conf.tpl /etc/odoo/odoo.conf.tpl
COPY --chown=odoo --chmod=755 entrypoint.sh /entrypoint.sh
COPY --chmod=755 wait-for-psql.py /usr/local/bin/wait-for-psql.py

EXPOSE 8069 8071 8072

USER odoo

ENTRYPOINT ["/entrypoint.sh"]
CMD ["odoo"]
