#!/bin/bash

# Aller au répertoire du script
cd "$(dirname "$0")" || exit 1

# ==============================================================================
# CONFIGURATION
# ==============================================================================
CHANNELS_FILE="channels.txt"
URLS_FILE="urls.txt"
OUTPUT_FILE="filtered_epg.xml"
TEMP_DIR="./temp_epg"

# Vérification des fichiers de configuration
for f in "$CHANNELS_FILE" "$URLS_FILE"; do
    if [[ ! -f "$f" ]]; then
        echo "Erreur : Le fichier $f est introuvable."
        exit 1
    fi
done

# --- 1. Lecture des chaînes et de leurs offsets ---
declare -A OFFSETS
CHANNEL_IDS=()

while IFS=',' read -r id offset || [[ -n "$id" ]]; do
    # Nettoyage (suppression espaces, ignore commentaires et lignes vides)
    id=$(echo "$id" | xargs)
    [[ -z "$id" || "$id" == \#* ]] && continue
    
    CHANNEL_IDS+=("$id")
    offset=$(echo "$offset" | xargs)
    
    # Normalisation de l'offset (ex: +2 devient +0200, -1 devient -0100)
    if [[ "$offset" =~ ^([+-])([0-9]+)$ ]]; then
        sign=${BASH_REMATCH[1]}
        num=${BASH_REMATCH[2]}
        OFFSETS["$id"]=$(printf "%s%02d00" "$sign" "$num")
    else
        OFFSETS["$id"]="" # Pas de modification si vide ou incorrect
    fi
done < "$CHANNELS_FILE"

# Lecture des URLs
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

mkdir -p "$TEMP_DIR"

# ==============================================================================
# PARAMÈTRES TEMPORELS
# ==============================================================================
NOW=$(date +%Y%m%d%H%M)
LIMIT=$(date -d "+3 days" +%Y%m%d%H%M)

# Construction des filtres XPath
xpath_channels=""
xpath_progs=""
for id in "${CHANNEL_IDS[@]}"; do
    xpath_channels+="@id='$id' or "
    xpath_progs+="@channel='$id' or "
done
xpath_channels="${xpath_channels% or }"
xpath_progs="${xpath_progs% or }"

echo "--- Démarrage du traitement ---"

# ==============================================================================
# 1. RÉCUPÉRATION ET FILTRAGE INDIVIDUEL
# ==============================================================================
count=0
for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [[ -z "$url" ]] && continue

    count=$((count + 1))
    echo "Source $count : $url"
    
    RAW_FILE="$TEMP_DIR/raw_$count.xml"
    SRC_FILE="$TEMP_DIR/src_$count.xml"
    
    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 10 --max-time 30 --fail "$url" | gunzip > "$RAW_FILE" 2>/dev/null
    else
        curl -sL --connect-timeout 10 --max-time 30 --fail "$url" > "$RAW_FILE" 2>/dev/null
    fi

    if [[ -s "$RAW_FILE" ]]; then
        # Filtrage initial (chaînes + dates)
        xmlstarlet ed \
            -d "/tv/channel[not($xpath_channels)]" \
            -d "/tv/programme[not($xpath_progs)]" \
            -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
            -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
            "$RAW_FILE" > "$SRC_FILE" 2>/dev/null

        # Application des offsets de fuseau horaire
        for id in "${!OFFSETS[@]}"; do
            new_tz="${OFFSETS[$id]}"
            if [[ -n "$new_tz" ]]; then
                # On remplace les 5 derniers caractères de l'attribut start/stop
                # Le format XMLTV est YYYYMMDDHHMMSS +HHMM (20 car. au total, fuseau commence à l'index 16)
                xmlstarlet ed -L \
                    -u "/tv/programme[@channel='$id']/@start" -x "concat(substring(@start,1,15), '$new_tz')" \
                    -u "/tv/programme[@channel='$id']/@stop"  -x "concat(substring(@stop,1,15), '$new_tz')" \
                    "$SRC_FILE"
            fi
        done
        rm -f "$RAW_FILE"
    else
        echo "Attention : Source $count injoignable ou vide."
    fi
done

# ==============================================================================
# 2. FUSION ET DÉDOUBLONNAGE
# ==============================================================================
echo "Fusion et suppression des doublons..."

echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# A. Chaînes uniques
xmlstarlet sel -t -c "/tv/channel" "$TEMP_DIR"/src_*.xml 2>/dev/null | \
    awk '!x[$0]++' >> "$OUTPUT_FILE"

# B. Programmes uniques (Clé = chaîne + heure de début)
xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/src_*.xml 2>/dev/null | \
    awk '
    BEGIN { RS="</programme>"; FS="<programme " }
    {
        if (match($0, /channel="([^"]+)"/, c) && match($0, /start="([^"]+)"/, s)) {
            key = c[1] s[1]
            if (!seen[key]++) {
                print $0 "</programme>"
            }
        }
    }' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# ==============================================================================
# NETTOYAGE
# ==============================================================================
rm -rf "$TEMP_DIR"

if [ -s "$OUTPUT_FILE" ]; then
    SIZE=$(du -sh "$OUTPUT_FILE" | cut -f1)
    echo "SUCCÈS : Fichier $OUTPUT_FILE créé ($SIZE)."
    gzip -f "$OUTPUT_FILE"
    echo "Succès : ${OUTPUT_FILE}.gz a été généré."
else
    echo "ERREUR : Le fichier final est vide."
fi
