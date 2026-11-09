# bodyvision-infra-compose – lancer tout BodyVision en local

Dépôt : <https://github.com/BodyVision-CCM/bodyvision-infra-compose>

Ce dépôt ne contient **aucun code de service** : seulement ce qui permet de faire tourner l'ensemble sur sa
machine : le `docker-compose.yml`, l'instance PostgreSQL partagée (avec un schéma et un rôle SQL par service) et la
configuration (`.env`). Chaque service vit dans **son propre dépôt**, et se teste seul.

## Démarrage minimal : PostgreSQL avec ses rôles et schémas

Un `git clone` suffit : rien d'autre à cloner pour avoir la base. Outils : Docker avec Compose v2 et `make`
(sous Windows : WSL).

```bash
git clone https://github.com/BodyVision-CCM/bodyvision-infra-compose.git
cd bodyvision-infra-compose
make db      # crée .env (secrets aléatoires), démarre PostgreSQL seul, puis vérifie les rôles et schémas
```

Sans `make` : `sh scripts/init-env.sh && docker compose up -d --wait postgres`. Le fichier `.env` n'est **pas** versionné
(il contient des secrets) : `make env` le crée avec des secrets aléatoires, et `.env.example` n'a que des valeurs vides.
Un `docker compose up` sans `.env` s'arrête en nommant la variable manquante.

Pour lancer aussi les services, il faut leurs dépôts à côté de celui-ci (section suivante).

## Prérequis pour lancer les services : les dépôts côte à côte

Le compose construit chaque service depuis le dossier frère de son dépôt. Clonez les dépôts **dans le même dossier** :

```bash
git clone https://github.com/BodyVision-CCM/bodyvision-infra-compose.git
git clone https://github.com/BodyVision-CCM/bodyvision-user-service.git     # service Auth (Utilisateurs)
```

```
projet/
├── bodyvision-infra-compose/   <- ce dépôt : c'est ici qu'on lance les commandes
├── bodyvision-user-service/    <- service Auth
└── (autres services, à venir)
```

`make up` vérifie leur présence et dit lequel manque. Si votre dossier porte un autre nom, indiquez-le avec
`AUTH_REPO_DIR` dans `.env` (chemin relatif à ce dépôt ; défaut `../bodyvision-user-service`).

## Démarrer

```bash
make env     # une seule fois : crée .env avec des secrets aléatoires (n'écrase jamais un .env existant)
make up      # construit et démarre PostgreSQL puis Auth, et attend qu'ils soient prêts
```

| Quoi | Où |
|---|---|
| **Swagger UI** du service Auth | http://localhost:8001/docs |
| Santé / métriques / clé publique JWT | http://localhost:8001/readyz · `/metrics` · `/.well-known/jwks.json` |
| PostgreSQL (DBeaver, psql) | `127.0.0.1:5432`, base `bodyvision` |

Autres commandes : `make down` (arrêt, données conservées) · `make logs` · `make ps` · `make psql` ·
`make config` · `make reset` (**efface les données locales** et rejoue l'initialisation des rôles et schémas ; `make up` relance ensuite les
services et leurs migrations) · `make help`.

Les **tests** d'un service se lancent dans le dépôt de ce service : `cd ../bodyvision-user-service && make test`.

## Rôles et schémas attendus (source de vérité)

Une seule instance PostgreSQL, base `bodyvision`, **un schéma et un rôle SQL par service** (ADR-001). Le service ne crée
**jamais** son schéma : il n'a pas le droit de création sur la base. C'est l'administrateur qui crée le rôle et le schéma
**avant** le premier démarrage du service. Cette liste est celle que SCRUM-49 reprend pour Cloud SQL.

| Service | Rôle SQL (défaut local) | Schéma | Variables du `.env` | Tables créées par |
|---|---|---|---|---|
| Auth (Utilisateurs) | `bv_utilisateurs` | `utilisateurs` | `AUTH_DB_USER`, `AUTH_DB_PASSWORD` | migrations Alembic du service Auth |
| Analytique (API et worker) | `bv_analytique` | `analytique` | `ANALYTIQUE_DB_USER`, `ANALYTIQUE_DB_PASSWORD` | migrations Alembic du service Analytique |
| Ingestion (Go) | **aucun** | **aucun** | n'en a pas | n'écrit pas en base (dépose sur le bucket et publie dans RabbitMQ) |

Le super-utilisateur (`POSTGRES_USER`) ne sert qu'à l'initialisation et à l'administration : aucun service ne l'utilise.

**Ce que `postgres/init/00_roles_schemas.sh` garantit, pour chaque rôle de service :**

- le rôle peut se connecter (`LOGIN`), n'est ni super-utilisateur ni créateur de base ou de rôle ;
- il est **propriétaire** de son schéma et seul à y accéder (`REVOKE ALL ... FROM PUBLIC`) : aucun accès croisé entre
  `utilisateurs` et `analytique` ;
- il n'a aucun accès au schéma `public`, et ne peut pas créer de schéma dans la base ;
- son `search_path` est son schéma (les migrations et le code n'ont pas à préfixer les tables).

Le script s'exécute **une seule fois**, au premier démarrage, quand le volume de données est vide. Pour le rejouer
(nouveau service, mot de passe changé) : `make reset` (efface les données locales, puis recrée les rôles et schémas et
les vérifie).

**Vérifier :** `make check-db` joue `postgres/verify.sql` et s'arrête au premier écart (rôle manquant, schéma d'un autre
propriétaire, droit de création de schéma, accès au schéma `public`, accès croisé, `search_path`). Ce fichier fonctionne
aussi sur Cloud SQL, avec n'importe quel compte administrateur :

```bash
psql -v ON_ERROR_STOP=1 -v auth_user=<rôle auth> -v ana_user=<rôle analytique> -d bodyvision -f postgres/verify.sql
```

### Équivalent dans le dépôt de chaque service

Le dépôt `bodyvision-user-service` teste contre une base **jetable** (`docker/test-db-init.sql`, mots de passe factices) pour rester autonome
en CI. Ce fichier est l'équivalent, pour le seul schéma `utilisateurs`, du script ci-dessus : comparés sur deux bases
vierges, ils donnent le même propriétaire, les mêmes droits (schéma, `public`, base), le même `search_path` et les mêmes
attributs de rôle. **Si un droit change ici, le changer aussi dans `docker/test-db-init.sql`** (et inversement).

### Sur GCP (Cloud SQL) : SCRUM-49

Ce dépôt est réservé au développement local ; il ne crée rien sur GCP. La création des rôles et des schémas sur
Cloud SQL **relève de SCRUM-49** (le service n'a pas les droits) et reprend la table ci-dessus :

1. un rôle et un schéma par service, mêmes noms, mêmes droits que ci-dessus (les ordres SQL sont dans
   `postgres/init/00_roles_schemas.sh`, à jouer avec le compte administrateur) ;
2. les **mots de passe** générés par SCRUM-49 et placés dans le gestionnaire de secrets, jamais dans un dépôt ;
3. vérifier avec `postgres/verify.sql`.

Point à valider sur Cloud SQL : l'administrateur y est un super-utilisateur restreint (`cloudsqlsuperuser`). Il peut devoir
être membre du rôle de service (`GRANT <rôle> TO <administrateur>`) pour créer un schéma dont ce rôle est propriétaire ;
`verify.sql` dira si le résultat est conforme.

## Ajouter un service

1. Cloner son dépôt à côté de celui-ci et l'ajouter à la vérification `check` du `Makefile`.
2. Copier le bloc `auth` du `docker-compose.yml` : `build: ${<SERVICE>_REPO_DIR:-../<dépôt du service>}` (et la variable
   dans `.env.example` et le `Makefile`), `depends_on: postgres: service_healthy`,
   variables `DB_*` avec **le rôle du service**, port `127.0.0.1:80xx:8000` (auth 8001, ingestion 8002, analytique 8003).
3. S'il a une base : ajouter son rôle et son schéma dans `postgres/init/00_roles_schemas.sh` **et** dans la liste
   `expected` de `postgres/verify.sql`, ses variables `<SERVICE>_DB_USER` / `<SERVICE>_DB_PASSWORD` dans `.env.example`
   et le bloc `postgres` du compose, une ligne dans la table « Rôles et schémas » ci-dessus, et prévenir SCRUM-49.
   L'Ingestion (Go) n'a **aucun** rôle : elle n'écrit pas en base.
4. Des modèles commentés pour RabbitMQ, Ingestion et Analytique (API et worker) sont déjà dans le compose.

## Configuration (`.env`)

Détail et commentaires : `.env.example`. `.env` est ignoré par Git (il contient les secrets) : chaque développeur
le crée avec `make env`. Les secrets (`*_PASSWORD`, `INTERNAL_SERVICE_TOKEN`) sont aléatoires.

| Variable | Rôle |
|---|---|
| `POSTGRES_PASSWORD` | Super-utilisateur : uniquement pour l'initialisation et `make psql` |
| `AUTH_DB_USER` / `AUTH_DB_PASSWORD` | Rôle SQL du service Auth |
| `INTERNAL_SERVICE_TOKEN` | Secret partagé des appels service-à-service (≥ 16 caractères) |
| `JWT_AUTOGENERATE_KEYS` | `true` : Auth crée sa clé RSA au 1er démarrage (volume `auth_keys`). **Local seulement** |
| `RUN_MIGRATIONS` | `true` : Auth joue ses migrations au démarrage |
| `AUTH_BIND_ADDRESS` | Optionnel. `0.0.0.0` pour joindre l'API depuis un téléphone sur le Wi-Fi (développement) |

Depuis l'émulateur Android, l'API de votre machine est joignable à `http://10.0.2.2:8001`.

## Périmètre

Cet environnement est **réservé au développement local** : secrets de développement, clé JWT auto-générée,
Swagger ouvert. Le déploiement sur GCP se fait service par service, depuis le dépôt de chaque service (son
`Dockerfile` à la racine) ; ce compose n'en fait pas partie.

## Ce qui est validé, et ce qui ne l'est pas

**Validé** (sur un PostgreSQL 16 réel) : le script d'init sur une base vierge ; `postgres/verify.sql` (conforme sur une base
initialisée par le script, et 6 écarts introduits volontairement, tous détectés) ; l'équivalence avec
`docker/test-db-init.sql` du service Auth ; le `docker-compose.yml` et le `.env` (`docker compose config`) ; la génération
du `.env` ; la vérification des dépôts frères ; le service Auth (70 tests), y compris `make test` dans Docker
(exécuté par l'équipe).

**À confirmer au premier essai** : le démarrage complet de cette pile dans Docker (`make db`, puis `make up`) n'a pas pu être
exécuté dans l'environnement de rédaction (pas de démon Docker). Si quelque chose échoue, `make logs` donne la cause, et
`make check-db` dit si les rôles et schémas sont conformes.
