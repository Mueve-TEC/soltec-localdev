# Makefile — soltec-localdev-odoo19
#
# Envoltorios sobre `docker compose` + Odoo CLI para no memorizar comandos.
# La base de datos Odoo se selecciona con DB (default: odoo). El módulo con
# MODULE (ej. `make upgrade MODULE=l10n_ar_tax`).
#
# Variables:
#   DB        Nombre de la base de datos Odoo (default: odoo)
#   MODULE    Módulo target para install/upgrade/test (default: base)
#   TEST_TAGS Filtro --test-tags extra (default: vacío = todos los tests del módulo)

DB      ?= odoo
MODULE  ?= base
TEST_TAGS ?=
ODOO_RUN   = $(DOCKER_COMPOSE) exec web
ODOO_RUN_RM = $(DOCKER_COMPOSE) run --rm web

ADDONS_PATH = /mnt/custom-addons,/usr/lib/python3/dist-packages/odoo/addons

# docker compose v2 plugin; override to `docker-compose` for the legacy v1 binary.
DOCKER_COMPOSE ?= docker compose

# ---------------------------------------------------------------------------
# Ciclo de vida del entorno
# ---------------------------------------------------------------------------
.PHONY: build up down down-clean logs ps shell restart
build:          ## Build de la imagen Odoo (usar tras cambiar el Dockerfile)
	$(DOCKER_COMPOSE) build --no-cache

up:             ## Levantar web + db + pgadmin (detached)
	$(DOCKER_COMPOSE) up -d

down:           ## Detener servicios
	$(DOCKER_COMPOSE) down

down-clean:     ## Detener y BORRAR volúmenes (DB, filestore, pgadmin)
	$(DOCKER_COMPOSE) down -v

logs:           ## Tail de logs de Odoo
	$(DOCKER_COMPOSE) logs -f web

ps:             ## Estado de los servicios
	$(DOCKER_COMPOSE) ps

shell:          ## Bash dentro del container Odoo
	$(DOCKER_COMPOSE) exec web bash

restart:        ## Restart del servicio web
	$(DOCKER_COMPOSE) restart web

# ---------------------------------------------------------------------------
# Módulos: sync submodules -> custom-addons, install, upgrade
# ---------------------------------------------------------------------------
.PHONY: sync install upgrade
sync:           ## Sincronizar submodules/ hacia custom-addons/ (copy_addons.sh)
	bash copy_addons.sh

install:        ## Instalar MODULE en DB  (docker compose exec web odoo -i)
	$(ODOO_RUN) odoo -d $(DB) -i $(MODULE) --stop-after-init

upgrade:        ## Actualizar MODULE en DB (docker compose exec web odoo -u)
	$(ODOO_RUN) odoo -d $(DB) -u $(MODULE) --stop-after-init

# ---------------------------------------------------------------------------
# Tests Odoo (--test-enable + --test-tags)
# ---------------------------------------------------------------------------
.PHONY: test test-install test-tags
test:           ## Correr tests de MODULE (upgrade + --test-enable)
	$(ODOO_RUN) odoo -d $(DB) -u $(MODULE) --test-enable \
		$(if $(TEST_TAGS),--test-tags='$(TEST_TAGS)') \
		--stop-after-init --log-level=info

test-install:   ## Correr tests de MODULE vía -i (instalación fresca)
	$(ODOO_RUN) odoo -d $(DB) -i $(MODULE) --test-enable \
		$(if $(TEST_TAGS),--test-tags='$(TEST_TAGS)') \
		--stop-after-init --log-level=info

# ---------------------------------------------------------------------------
# Base de datos / shell
# ---------------------------------------------------------------------------
.PHONY: dbshell odoo-shell init-db
dbshell:        ## psql dentro del container postgres
	$(DOCKER_COMPOSE) exec db psql -U odoo -d $(DB)

odoo-shell:     ## Odoo shell (prompt Python con env/registry)
	$(ODOO_RUN) odoo shell -d $(DB)

# ---------------------------------------------------------------------------
# Submódulos git
# ---------------------------------------------------------------------------
.PHONY: submodules-init submodules-update
submodules-init:    ## Inicializar todos los submódulos recursivamente
	git submodule update --init --recursive

submodules-update:  ## Actualizar cada submódulo a la punta de su branch
	git submodule update --remote --merge

# ---------------------------------------------------------------------------
# Lint / format (a nivel supermódulo — ver AGENTS.md para submódulos)
# ---------------------------------------------------------------------------
.PHONY: lint lint-check format
lint:           ## Correr pre-commit sobre todos los archivos del supermódulo
	pre-commit run --all-files

lint-check:     ## Correr pre-commit sin autofix (verificación en CI)
	pre-commit run --all-files --no-stash

format:         ## Aplicar ruff format + prettier a archivos del supermódulo
	pre-commit run ruff --all-files || true
	pre-commit run prettier --all-files || true

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
.DEFAULT_GOAL := help
help:           ## Mostrar esta ayuda
	@awk 'BEGIN {FS = ":.*##"; printf "Uso:\n  make <target> [DB=...] [MODULE=...] [TEST_TAGS=...]\n\nTargets:\n"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
