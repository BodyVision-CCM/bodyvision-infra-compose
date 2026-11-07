-- Vérifie que l'instance PostgreSQL a bien les rôles et schémas attendus (voir README, « Rôles et schémas »).
-- Lancé par `make check-db` (et utilisable tel quel sur Cloud SQL : SCRUM-49), en super-utilisateur :
--   psql -v ON_ERROR_STOP=1 -v auth_user=bv_utilisateurs -v ana_user=bv_analytique -d bodyvision -f verify.sql
-- Lève une exception (code retour non nul) au premier écart ; n'écrit rien dans la base.

SELECT set_config('bv.auth_user', :'auth_user', false) AS _ \gset
SELECT set_config('bv.ana_user',  :'ana_user',  false) AS _ \gset

DO $$
DECLARE
    -- (rôle, schéma) attendus : UNE ligne par service qui a une base. Ingestion n'en a pas (n'écrit pas en base).
    expected text[][] := ARRAY[
        [current_setting('bv.auth_user'), 'utilisateurs'],
        [current_setting('bv.ana_user'),  'analytique']
    ];
    r text; s text; o text; r2 text; s2 text;
    i int; j int;
BEGIN
    FOR i IN 1 .. array_length(expected, 1) LOOP
        r := expected[i][1]; s := expected[i][2];

        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r AND rolcanlogin) THEN
            RAISE EXCEPTION 'ECHEC : le rôle % n''existe pas ou ne peut pas se connecter', r;
        END IF;
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)) THEN
            RAISE EXCEPTION 'ECHEC : le rôle % a trop de droits (super-utilisateur, création de base ou de rôle...)', r;
        END IF;

        SELECT pg_get_userbyid(nspowner) INTO o FROM pg_namespace WHERE nspname = s;
        IF o IS NULL THEN RAISE EXCEPTION 'ECHEC : le schéma % n''existe pas', s; END IF;
        IF o <> r THEN RAISE EXCEPTION 'ECHEC : le schéma % appartient à %, attendu %', s, o, r; END IF;

        IF NOT has_schema_privilege(r, s, 'USAGE') OR NOT has_schema_privilege(r, s, 'CREATE') THEN
            RAISE EXCEPTION 'ECHEC : % doit pouvoir utiliser et créer des tables dans %', r, s;
        END IF;
        -- Le service ne doit PAS pouvoir créer de schéma (la création est déléguée à l'administrateur).
        IF has_database_privilege(r, current_database(), 'CREATE') THEN
            RAISE EXCEPTION 'ECHEC : % peut créer des schémas dans la base (droit CREATE sur la base)', r;
        END IF;
        IF has_schema_privilege(r, 'public', 'USAGE') OR has_schema_privilege(r, 'public', 'CREATE') THEN
            RAISE EXCEPTION 'ECHEC : % a accès au schéma public', r;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r AND ('search_path=' || s) = ANY (rolconfig)) THEN
            RAISE EXCEPTION 'ECHEC : le search_path de % devrait être %', r, s;
        END IF;

        -- Étanchéité : aucun autre rôle de service n'accède à ce schéma.
        FOR j IN 1 .. array_length(expected, 1) LOOP
            r2 := expected[j][1]; s2 := expected[j][2];
            IF j <> i AND (has_schema_privilege(r2, s, 'USAGE') OR has_schema_privilege(r2, s, 'CREATE')) THEN
                RAISE EXCEPTION 'ECHEC : % a accès au schéma % qui n''est pas le sien', r2, s;
            END IF;
        END LOOP;
        RAISE NOTICE 'ok  % -> schéma % (propriétaire, droits, search_path, étanchéité)', r, s;
    END LOOP;

    RAISE NOTICE 'ok  % rôle(s) et schéma(s) conformes à la liste du README', array_length(expected, 1);
END $$;
