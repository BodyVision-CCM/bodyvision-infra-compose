#!/bin/sh
# Initialisation de l'instance PostgreSQL partagée (exécutée UNE SEULE FOIS, au premier démarrage
# du conteneur, quand le volume de données est vide : mécanisme /docker-entrypoint-initdb.d).
#
# Principe (ADR-001) : une instance, un schéma par service, un rôle SQL par service limité à son
# schéma. Les tables sont créées ensuite par les migrations Alembic de chaque service.
# Le service Ingestion (Go) n'a volontairement aucun rôle : il n'écrit pas en base.
#
# Pour ajouter un service qui a une base : ajouter son rôle + son schéma ci-dessous, et ses
# variables <SERVICE>_DB_USER / <SERVICE>_DB_PASSWORD dans .env et dans docker-compose.yml.
#
# `set -e` seulement (pas `-u`) : si ce fichier n'est pas exécutable (checkout Windows), l'image
# postgres le SOURCE dans son propre shell, et `-u` s'appliquerait alors à son entrypoint. Les variables
# obligatoires sont de toute façon vérifiées une par une avec `:?` ci-dessous.
set -e

: "${AUTH_DB_USER:?AUTH_DB_USER manquant}"
: "${AUTH_DB_PASSWORD:?AUTH_DB_PASSWORD manquant}"
: "${ANALYTIQUE_DB_USER:?ANALYTIQUE_DB_USER manquant}"
: "${ANALYTIQUE_DB_PASSWORD:?ANALYTIQUE_DB_PASSWORD manquant}"

# Heredoc entre quotes : le shell ne touche à rien. Les identifiants (:"x") et les littéraux
# (:'x') sont échappés par psql lui-même, donc un mot de passe contenant ' ou $ reste sûr.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v auth_user="$AUTH_DB_USER" -v auth_pw="$AUTH_DB_PASSWORD" \
  -v ana_user="$ANALYTIQUE_DB_USER" -v ana_pw="$ANALYTIQUE_DB_PASSWORD" <<'EOSQL'

CREATE ROLE :"auth_user" LOGIN PASSWORD :'auth_pw';
CREATE ROLE :"ana_user"  LOGIN PASSWORD :'ana_pw';

CREATE SCHEMA utilisateurs AUTHORIZATION :"auth_user";
CREATE SCHEMA analytique   AUTHORIZATION :"ana_user";

-- Étanchéité : seul le propriétaire accède à un schéma ; personne n'utilise "public".
REVOKE ALL ON SCHEMA utilisateurs FROM PUBLIC;
REVOKE ALL ON SCHEMA analytique   FROM PUBLIC;
REVOKE ALL ON SCHEMA public       FROM PUBLIC;

-- Chaque rôle travaille par défaut dans son propre schéma.
ALTER ROLE :"auth_user" SET search_path = utilisateurs;
ALTER ROLE :"ana_user"  SET search_path = analytique;

EOSQL
