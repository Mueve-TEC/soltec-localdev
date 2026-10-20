# Makefile — soltec-localdev-odoo19
#
# Envoltorios sobre `docker compose` + Odoo CLI para no memorizar comandos.
# La base de datos Odoo se selecciona con DB (default: odoo). El módulo con
# MODULE (ej. `make upgrade MODULE=l10n_ar_tax`).
#
# Variables:
#   DB        Nombre de la base de datos Odoo (default: odoo; en un worktree de
#             ticket se toma automáticamente de .ticket/env.mk)
#   MODULE    Módulo target para install/upgrade/test (default: base)
#   TEST_TAGS Filtro --test-tags extra (default: vacío = todos los tests del módulo)
#   SLUG      Ticket para los targets ticket-* (opcional dentro del worktree)

# Escrito por `make ticket-new`; ausente en el checkout principal.
-include .ticket/env.mk

DB      ?= $(if $(TICKET_DB),$(TICKET_DB),odoo)
MODULE  ?= base
TEST_TAGS ?=
HTTP_PORT ?= 8099
SLUG ?=
SRC_DB ?= admin
ODOO_RUN   = $(DOCKER_COMPOSE) exec web
ODOO_RUN_RM = $(DOCKER_COMPOSE) run --rm web

ADDONS_PATH = /mnt/custom-addons,/mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons

# Base Odoo CLI command with proper addons-path and DB connection args.
# Use this for all CLI invocations (Gotcha #12).
ODOO_CMD = odoo \
	--addons-path=$(ADDONS_PATH) \
	--db_host=db --db_user=odoo --db_password=odoo \
	--http-port=$(HTTP_PORT)

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
	@bash scripts/ticket.sh guard-down-clean
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
	$(ODOO_RUN) $(ODOO_CMD) -d $(DB) -i $(MODULE) --stop-after-init

upgrade:        ## Actualizar MODULE en DB (docker compose exec web odoo -u)
	$(ODOO_RUN) $(ODOO_CMD) -d $(DB) -u $(MODULE) --stop-after-init

# ---------------------------------------------------------------------------
# Tests Odoo (--test-enable + --test-tags)
# ---------------------------------------------------------------------------
.PHONY: test test-install test-raw test-install-raw
test:           ## Correr tests de MODULE (upgrade + --test-enable, output filtrado)
	@bash scripts/test-runner.sh $(ODOO_RUN) $(ODOO_CMD) -d $(DB) -u $(MODULE) \
		--test-enable $(if $(TEST_TAGS),--test-tags='$(TEST_TAGS)') \
		--stop-after-init --log-level=info

test-install:   ## Correr tests de MODULE vía -i (instalación fresca, output filtrado)
	@bash scripts/test-runner.sh $(ODOO_RUN) $(ODOO_CMD) -d $(DB) -i $(MODULE) \
		--test-enable $(if $(TEST_TAGS),--test-tags='$(TEST_TAGS)') \
		--stop-after-init --log-level=info

test-raw:       ## Correr tests de MODULE SIN filtrar (output completo de Odoo)
	$(ODOO_RUN) $(ODOO_CMD) -d $(DB) -u $(MODULE) --test-enable \
		$(if $(TEST_TAGS),--test-tags='$(TEST_TAGS)') \
		--stop-after-init --log-level=info

test-install-raw: ## Correr tests de MODULE vía -i SIN filtrar
	$(ODOO_RUN) $(ODOO_CMD) -d $(DB) -i $(MODULE) --test-enable \
		$(if $(TEST_TAGS),--test-tags='$(TEST_TAGS)') \
		--stop-after-init --log-level=info

# ---------------------------------------------------------------------------
# Base de datos / shell
# ---------------------------------------------------------------------------
.PHONY: dbshell odoo-shell init-db
dbshell:        ## psql dentro del container postgres
	$(DOCKER_COMPOSE) exec db psql -U odoo -d $(DB)

odoo-shell:     ## Odoo shell (prompt Python con env/registry)
	$(ODOO_RUN) $(ODOO_CMD) shell -d $(DB)

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
.PHONY: lint lint-check format lint-odoo-ar
lint:           ## Correr pre-commit sobre todos los archivos del supermódulo
	pre-commit run --all-files

lint-check:     ## Correr pre-commit sin autofix (verificación en CI)
	pre-commit run --all-files --no-stash

format:         ## Aplicar ruff format + prettier a archivos del supermódulo
	pre-commit run ruff --all-files || true
	pre-commit run prettier --all-files || true

lint-odoo-ar:   ## Pre-commit (stack adhoc completo) dentro de submodules/odoo-argentina
	@cd submodules/odoo-argentina && pre-commit run --all-files

# ---------------------------------------------------------------------------
# Tickets en worktrees paralelos (ver AGENTS.md, "Parallel ticket worktrees")
# ---------------------------------------------------------------------------
.PHONY: ticket-new ticket-up ticket-down ticket-logs ticket-shell ticket-dbshell \
	ticket-upgrade ticket-test ticket-list ticket-done golden-refresh

ticket-new:     ## Crear ticket completo: worktree + branches + DB + filestore + web
	@bash scripts/ticket.sh new $(SLUG)

ticket-up:      ## Levantar el web del ticket (inicia db del stack principal si hace falta)
	@bash scripts/ticket.sh up $(SLUG)

ticket-down:    ## Detener el web del ticket (conserva DB y volúmenes)
	@bash scripts/ticket.sh down $(SLUG)

ticket-logs:    ## Logs del web del ticket
	@bash scripts/ticket.sh logs $(SLUG)

ticket-shell:   ## Bash dentro del container web del ticket
	@bash scripts/ticket.sh shell $(SLUG)

ticket-dbshell: ## psql sobre la DB del ticket
	@bash scripts/ticket.sh dbshell $(SLUG)

ticket-upgrade: ## Actualizar MODULE en la DB del ticket
	@MODULE='$(MODULE)' bash scripts/ticket.sh upgrade $(SLUG)

ticket-test:    ## Correr tests de MODULE en la DB del ticket
	@MODULE='$(MODULE)' TEST_TAGS='$(TEST_TAGS)' bash scripts/ticket.sh test $(SLUG)

ticket-list:    ## Listar tickets, DBs y estado del web
	@bash scripts/ticket.sh list

ticket-done:    ## Eliminar ticket (worktree + DB + volúmenes); KEEP=1 / FORCE=1
	@bash scripts/ticket.sh done $(SLUG)

golden-refresh: ## Recrear la DB golden desde SRC_DB (default: admin)
	@SRC_DB='$(SRC_DB)' bash scripts/ticket.sh golden-refresh

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
.DEFAULT_GOAL := help
help:           ## Mostrar esta ayuda
	@awk 'BEGIN {FS = ":.*##"; printf "Uso:\n  make <target> [DB=...] [MODULE=...] [TEST_TAGS=...]\n\nTargets:\n"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
