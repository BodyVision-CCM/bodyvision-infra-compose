#!/bin/sh
# Crée le fichier `.env` à partir de `.env.example` et génère des secrets aléatoires.
#
# `.env` est ignoré par Git (il contient des secrets) : chaque développeur doit donc le créer lui-même
# après avoir cloné le dépôt. C'est ce que fait ce script, en une commande :   make env
#
# - N'écrase JAMAIS un `.env` existant.
# - Ne remplit que les valeurs vides *_PASSWORD et INTERNAL_SERVICE_TOKEN ; le reste vient de .env.example.
# - Secrets en hexadécimal (24 octets = 48 caractères) : aucun caractère spécial que Docker Compose
#   ou le shell pourraient interpréter.
set -eu

cd "$(dirname "$0")/.."

if [ -f .env ]; then
    echo ".env existe déjà : rien à faire (supprimez-le d'abord pour le régénérer)."
    exit 0
fi
[ -f .env.example ] || { echo "ERREUR : .env.example introuvable." >&2; exit 1; }

secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 24
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import secrets; print(secrets.token_hex(24))"
    else
        echo "ERREUR : il faut openssl ou python3 pour générer des secrets." >&2
        exit 1
    fi
}

: > .env
CR=$(printf '\r')
while IFS= read -r line || [ -n "$line" ]; do
    line=${line%"$CR"}   # tolère un .env.example en CRLF (checkout Windows sans .gitattributes)
    case "$line" in
        [A-Z_]*_PASSWORD=|INTERNAL_SERVICE_TOKEN=)
            printf '%s%s\n' "$line" "$(secret)" >> .env ;;
        *)
            printf '%s\n' "$line" >> .env ;;
    esac
done < .env.example

# Garde-fou : on n'annonce « secrets générés » que si c'est vrai.
if grep -Eq '^([A-Z_]*_PASSWORD|INTERNAL_SERVICE_TOKEN)=$' .env; then
    rm -f .env
    echo "ERREUR : un secret est resté vide : .env supprimé. Vérifiez que .env.example est bien en fins de ligne Unix (LF)." >&2
    exit 1
fi

chmod 600 .env 2>/dev/null || true
echo ".env créé avec des secrets aléatoires. Ne le commitez pas (déjà dans .gitignore)."
