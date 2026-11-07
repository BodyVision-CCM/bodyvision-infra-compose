# Raccourcis pour lancer tous les services en local. `make help` liste les commandes.
# Les tests d'un service se lancent dans le dépôt de ce service (`make test` dans ../auth).
# (Sous Windows : utilisez WSL, ou lancez directement les commandes `docker compose` indiquées.)

COMPOSE := docker compose

# Dépôts de services qui doivent être clonés À CÔTÉ de infra-compose (un dossier frère par service).
# Ajouter ici chaque nouveau service construit par le compose.
SERVICES := auth

.DEFAULT_GOAL := help
.PHONY: help env check db check-db up down logs ps config psql reset

help: ## Affiche cette aide
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-9s %s\n", $$1, $$2}'

env: ## Crée .env avec des secrets aléatoires (sans jamais écraser un .env existant)
	@sh scripts/init-env.sh

check: ## Vérifie que les dépôts des services sont bien clonés à côté de infra-compose
	@for s in $(SERVICES); do \
	  [ -f ../$$s/Dockerfile ] || { echo "ERREUR : le dépôt '$$s' doit être cloné à côté de infra-compose (attendu : ../$$s/Dockerfile)."; exit 1; }; \
	done; echo "dépôts des services : OK ($(SERVICES))"

db: ## Démarre PostgreSQL SEUL (crée .env si besoin) et vérifie les rôles et schémas : rien d'autre à cloner
	@[ -f .env ] || sh scripts/init-env.sh
	$(COMPOSE) up -d --wait postgres
	@$(MAKE) --no-print-directory check-db

check-db: ## Vérifie que les rôles et schémas attendus existent et sont étanches (postgres/verify.sql)
	@out=$$($(COMPOSE) exec -T postgres sh -c 'psql -q -v ON_ERROR_STOP=1 -v auth_user="$$AUTH_DB_USER" -v ana_user="$$ANALYTIQUE_DB_USER" -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"' < postgres/verify.sql 2>&1); rc=$$?; \
	  printf '%s\n' "$$out" | sed -e 's/^.*NOTICE:  //' -e 's/^.*ERROR:  //'; exit $$rc

up: check ## Construit et démarre PostgreSQL + Auth (Swagger : http://localhost:8001/docs)
	$(COMPOSE) up -d --build --wait
	@$(MAKE) --no-print-directory check-db
	@echo ""
	@echo "  Swagger UI  : http://localhost:8001/docs   (port = AUTH_HOST_PORT dans .env)"
	@echo "  Santé       : http://localhost:8001/readyz"

down: ## Arrête les conteneurs (les données PostgreSQL sont conservées)
	$(COMPOSE) down

logs: ## Suit les logs de tous les services (Ctrl+C pour quitter)
	$(COMPOSE) logs -f --tail=100

ps: ## État des conteneurs
	$(COMPOSE) ps

config: ## Vérifie le docker-compose.yml et le .env (affiche la configuration résolue)
	$(COMPOSE) config

psql: ## Ouvre psql dans la base, en super-utilisateur
	$(COMPOSE) exec postgres sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"'

reset: ## DESTRUCTIF : efface les données et rejoue l'initialisation (rôles, schémas, migrations)
	@printf "Cela supprime TOUTES les données locales (volumes). Continuer ? [y/N] " && read ans && [ "$$ans" = "y" ]
	$(COMPOSE) down -v
