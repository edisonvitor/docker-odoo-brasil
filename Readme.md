# Odoo 18 com localização brasileira (OCA) em Docker

**Português** | [English](Readme.en.md)

Imagem Docker do **Odoo 18.0 Community** com a localização brasileira do [OCA l10n-brazil](https://github.com/OCA/l10n-brazil) (NF-e, NFS-e, CT-e, MDF-e, fiscal, contabilidade, boletos/CNAB) e os repositórios OCA de que ela depende.

A base é a imagem oficial [`odoo:18.0`](https://hub.docker.com/_/odoo), sobre Ubuntu Noble com Python 3.12. Os addons vêm no próprio build da imagem, sem `.git`. A pasta [`addons/`](addons/) fica para os seus módulos.

Repositórios incluídos (branch `18.0`):

`OCA/l10n-brazil`, `web`, `server-ux`, `reporting-engine`, `account-reconcile`, `account-financial-reporting`, `account-financial-tools`, `account-payment`, `account-invoicing`, `bank-payment`, `mis-builder`, `commission`, `currency`, `delivery-carrier`, `hr`, `product-attribute`, `brand`, `purchase-workflow`, `sale-workflow`, `queue` e `odoo/design-themes`.

## Desenvolvimento

```bash
docker compose up -d
```

O [docker-compose.yml](docker-compose.yml) faz o build da imagem e sobe o Postgres 16. O Odoo fica em http://localhost:8069 e a pasta `./addons` é montada como `extra-addons`. Ela vem primeiro no `addons_path`, então um módulo seu substitui um módulo OCA de mesmo nome.

O usuário e a senha do banco são `odoo`/`odoo`, e a senha master é `admin`. Use esse compose só na sua máquina.

Para criar um banco e instalar os módulos brasileiros:

```bash
docker compose run --rm -e WORKERS=0 odoo odoo -d meubanco \
    -i l10n_br_base,l10n_br_fiscal,l10n_br_account,l10n_br_nfe,l10n_br_nfse,l10n_br_sale,l10n_br_purchase,l10n_br_coa_generic \
    --stop-after-init --without-demo=all
```

Se faltar o repositório de alguma dependência, o comando falha logo no início. Isso faz dele também um bom teste rápido da imagem.

## Produção

O [docker-compose.prod.yml](docker-compose.prod.yml) sobe três serviços:

- **Caddy**: proxy reverso com HTTPS automático (Let's Encrypt). Só ele expõe portas, a 80 e a 443.
- **Odoo**: configurado pelo `.env` e acessível só pela rede interna do compose.
- **Postgres 16**: sem porta exposta e com healthcheck.

Os logs ficam no stdout (`docker compose logs`), com rotação de 5 arquivos de 50 MB.

### Pré-requisitos

- Um domínio com o DNS apontando para o servidor.
- Portas 80 e 443 abertas.

### Subindo

```bash
cp .env.example .env
# edite o .env: DOMAIN, senhas (openssl rand -base64 32), DATABASE, SMTP...

# cria o banco e instala os módulos (uma vez)
docker compose -f docker-compose.prod.yml run --rm -e WORKERS=0 odoo odoo -d producao \
    -i l10n_br_base,l10n_br_account,l10n_br_coa_generic \
    --stop-after-init --without-demo=all

docker compose -f docker-compose.prod.yml up -d
```

O valor de `-d` precisa ser igual ao `DATABASE` do `.env`. O primeiro acesso é feito com o usuário `admin` e a senha `admin`. **Troque essa senha logo no primeiro acesso.**

O `.env.example` já vem com `LIST_DB=False`, o que desliga o gerenciador de bancos (`/web/database/manager`). Na internet, deixe assim. Com ele ligado, qualquer pessoa que descubra a senha master consegue baixar ou apagar os bancos.

### Por que `env_file` e não `${VAR}`

A imagem usa variáveis com nomes genéricos (`USER`, `HOST`, `PORT`, `PASSWORD`). Na interpolação `${VAR}` do compose, as variáveis do shell têm prioridade sobre o `.env`, e aí `${USER}` viraria o seu usuário do Linux. Com `env_file: .env`, os valores vão direto para o container.

Se preferir não guardar a senha do banco em variável, use `PASSWORD_FILE` apontando para um arquivo, por exemplo um Docker secret.

### Imagem publicada e versões fixas

O [GitHub Actions](.github/workflows/build.yml) faz o build e publica a imagem em [`ghcr.io/edisonvitor/odoo-brasil`](https://github.com/edisonvitor/docker-odoo-brasil/pkgs/container/odoo-brasil). Isso acontece a cada push no `main`, toda segunda-feira (para pegar as correções da OCA) e quando o workflow é disparado à mão. Antes de publicar, o workflow instala os principais módulos num Postgres temporário. Se alguma dependência faltar, a imagem não é publicada.

| Tag | Uso |
|---|---|
| `18.0` | Build mais recente |
| `18.0-AAAAMMDD` | Fixa, para produção |
| `sha-<commit>` | Rastreia de qual commit a imagem saiu |

O build clona o topo da branch `18.0` de cada repositório OCA, então builds de dias diferentes geram imagens diferentes. Em produção, use uma tag com data no `ODOO_IMAGE` e teste em homologação antes de trocar. Para voltar atrás, basta apontar de novo para a tag anterior.

### Atualizando módulos

Depois de trocar o `ODOO_IMAGE` por uma versão nova, baixe a imagem e atualize os módulos que mudaram:

```bash
docker compose -f docker-compose.prod.yml pull odoo
docker compose -f docker-compose.prod.yml run --rm -e WORKERS=0 odoo \
    click-odoo-update -c /etc/odoo/odoo.conf -d producao
```

Faça backup antes de atualizar.

### Backup

O backup precisa de duas partes: o banco e o filestore, onde ficam os anexos, XMLs de NF-e e certificados.

```bash
mkdir -p backups
docker compose -f docker-compose.prod.yml exec -T db \
    sh -c 'pg_dump -U "$POSTGRES_USER" -Fc producao' > backups/producao-$(date +%F).dump
docker compose -f docker-compose.prod.yml exec -T odoo \
    tar czf - -C /var/lib/odoo/filestore producao > backups/filestore-$(date +%F).tar.gz
```

Agende esses comandos (cron) e guarde as cópias **fora do servidor**.

## Variáveis de ambiente

O `entrypoint.sh` gera o `/etc/odoo/odoo.conf` a partir do [odoo.conf.tpl](odoo.conf.tpl) a cada start. Para mudar a configuração, basta trocar a variável e reiniciar o container.

| Variável | Padrão | Descrição |
|---|---|---|
| `HOST` | `localhost` | Host do Postgres |
| `PORT` | `5432` | Porta do Postgres |
| `USER` | `odoo` | Usuário do Postgres |
| `PASSWORD` | `odoo` | Senha do Postgres |
| `PASSWORD_FILE` | — | Arquivo com a senha do Postgres. Tem prioridade sobre `PASSWORD`. |
| `ODOO_PASSWORD` | `admin` | Senha master (`admin_passwd`). **Troque em produção.** |
| `DATABASE` | `False` | Banco padrão (`db_name`) |
| `DB_FILTER` | `False` | Regex de bancos visíveis (`dbfilter`) |
| `LIST_DB` | `True` | Gerenciador de bancos. Use `False` em produção. |
| `WORKERS` | `5` | Processos HTTP. Precisa ser maior que 0 por causa do `queue_job`. |
| `QUEUE_JOB_CHANNELS` | `root:2` | Canais do `queue_job` |
| `LIMIT_MEMORY_SOFT` | `2147483648` | Memória por worker antes de reciclar (bytes) |
| `LIMIT_MEMORY_HARD` | `2684354560` | Memória máxima por worker (bytes) |
| `TIME_CPU` | `6000` | `limit_time_cpu` (s) |
| `TIME_REAL` | `7200` | `limit_time_real` (s) |
| `ODOO_PORT` | `8069` | Porta HTTP |
| `LONGPOLLING_PORT` | `8072` | `gevent_port` (websocket) |
| `LOG_FILE` | `False` | `False` manda o log para o stdout. Também aceita um caminho, por exemplo `/var/lib/odoo/odoo.log`. |
| `DEBUG_MODE` | `False` | `debug_mode` |
| `EMAIL_FROM` | `odoo@teste.com` | Remetente padrão |
| `SMTP_SERVER` | `localhost` | Servidor SMTP |
| `SMTP_PORT` | `25` | Porta SMTP |
| `SMTP_SSL` | `False` | SMTP com SSL |
| `SMTP_USER` | `False` | Usuário SMTP |
| `SMTP_PASSWORD` | `False` | Senha SMTP |

O `queue_job`, usado pelo l10n-brazil, já está em `server_wide_modules`.

## Build

```bash
docker build -t craines/odoo-brasil:18.0 .
docker build --build-arg ODOO_TAG=18.0-20261015 --build-arg ADDONS_BRANCH=18.0 -t craines/odoo-brasil:18.0 .
```

- `ODOO_TAG` é a tag da imagem oficial `odoo`.
- `ADDONS_BRANCH` é a branch clonada dos repositórios OCA.

Para incluir outro repositório OCA, adicione-o na lista `for repo in` do [Dockerfile](Dockerfile). Ele precisa ter branch `18.0`, e o `requirements.txt` dele é instalado automaticamente.

## Módulos úteis

Todos já estão na imagem. Por não serem marcados como "aplicativo", não aparecem na tela **Aplicativos** com o filtro padrão. Para encontrá-los, ative o modo desenvolvedor, clique em *Atualizar lista de aplicativos*, remova o filtro "Aplicativos" e busque pelo nome técnico.

| Para | Módulos |
|---|---|
| Plano de contas | `l10n_br_coa_simple` (ME/EPP, ITG 1000) ou `l10n_br_coa_generic` (regime normal) |
| Faturamento BR | `l10n_br_account`, `account_usability` (mostra os menus contábeis) |
| Contas a pagar/receber | `l10n_br_account_due_list`, `l10n_br_account_payment_order` |
| Boletos e CNAB | `l10n_br_account_payment_brcobranca` (precisa do serviço [boleto_cnab_api](https://github.com/akretion/boleto_cnab_api)), `l10n_br_cnab_structure` |
| Conciliação bancária | `account_reconcile_oca` |
| Relatórios | `l10n_br_mis_report` (Balanço e DRE), `mis_builder_cash_flow`, `account_financial_report` |
| Notas fiscais | `l10n_br_nfe`, `l10n_br_nfse` |
| Interface | `web_responsive`, `web_dark_mode` |

## Histórico

Até a versão 15.0, esta imagem usava o `odoo-brasil`/`trustcode-addons` da Trust-Code e o code-137. Esses projetos foram abandonados e saíram da imagem. **Não existe caminho de migração** de bancos 15.0 desses módulos para esta versão.

## Licença

[AGPL-3.0](LICENSE). Os módulos incluídos na imagem mantêm as próprias licenças: AGPL-3 ou LGPL-3 nos módulos OCA e LGPL-3 no Odoo.
