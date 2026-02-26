#!/bin/bash

# Aller au répertoire du script
cd "$(dirname "$0")" || exit 1

# ==============================================================================
# CONFIGURATION
# ==============================================================================
CHANNELS_FILE="channels.txt"
URLS_FILE="urls.txt"
OUTPUT_FILE="epg.xml"
TEMP_DIR="./temp_epg"

# Vérification des fichiers
for f in "$CHANNELS_FILE" "$URLS_FILE"; do
    if [[ ! -f "$f" ]]; then
        echo "Erreur : Le fichier $f est introuvable."
        exit 1
    fi
done

# 1. CHARGEMENT DU MAPPING
declare -A ID_MAP
CHANNEL_IDS=()

while IFS=',' read -r old_id new_id || [[ -n "$old_id" ]]; do
    [[ "$old_id" =~ ^\s*(#|$) ]] && continue
    old_clean=$(echo "$old_id" | tr -d '\r' | xargs)
    new_clean=$(echo "$new_id" | tr -d '\r' | xargs)
    
    if [[ -n "$old_clean" && -n "$new_clean" ]]; then
        ID_MAP["$old_clean"]="$new_clean"
        CHANNEL_IDS+=("$old_clean")
    fi
done < "$CHANNELS_FILE"

mkdir -p "$TEMP_DIR"

# PARAMÈTRES TEMPORELS
NOW=$(date +%Y%m%d%H%M)
LIMIT=$(date -d "+1 days" +%Y%m%d%H%M)

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
# 2. RÉCUPÉRATION ET FILTRAGE XMLSTARLET
# ==============================================================================
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

count=0
for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [[ -z "$url" ]] && continue

    count=$((count + 1))
    echo "Source $count : $url"
    RAW_FILE="$TEMP_DIR/raw_$count.xml"
    
    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 10 --max-time 30 --fail "$url" | gunzip > "$RAW_FILE" 2>/dev/null
    else
        curl -sL --connect-timeout 10 --max-time 30 --fail "$url" > "$RAW_FILE" 2>/dev/null
    fi

    if [[ -s "$RAW_FILE" ]]; then
        if ! xmlstarlet ed \
            -d "/tv/channel[not($xpath_channels)]" \
            -d "/tv/programme[not($xpath_progs)]" \
            -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
            -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
            "$RAW_FILE" > "$TEMP_DIR/src_$count.xml" 2>/dev/null; then
            echo "Attention : Erreur XML source $count"
        fi
        rm -f "$RAW_FILE"
    else
        echo "Attention : Source $count vide ou erreur"
    fi
done

# ==============================================================================
# 3. FUSION ET DÉDOUBLONNAGE ROBUSTE
# ==============================================================================
echo "Fusion et traitement final..."

echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# --- A. Traitement des CHANNELS ---
for old_id in "${!ID_MAP[@]}"; do
    new_id=${ID_MAP[$old_id]}
    xmlstarlet sel -t -c "/tv/channel[@id='$old_id']" "$TEMP_DIR"/*.xml 2>/dev/null | \
    sed "s/id=\"$old_id\"/id=\"$new_id\"/g" >> "$TEMP_DIR/all_channels.tmp"
done

if [[ -f "$TEMP_DIR/all_channels.tmp" ]]; then
    awk 'match($0, /id="([^"]+)"/, a) { if (!seen[a[1]]++) print $0 }' "$TEMP_DIR/all_channels.tmp" >> "$OUTPUT_FILE"
fi

# --- B. Traitement des PROGRAMMES ---
# Préparation sécurisée de la chaîne de mapping pour AWK
MAP_STR=""
for old in "${!ID_MAP[@]}"; do
    MAP_STR+="${old}=${ID_MAP[$old]};"
done

xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/*.xml 2>/dev/null | \
awk -v mapping="$MAP_STR" '
BEGIN { 
    RS="</programme>"; 
    split(mapping, m_arr, ";");
    for (i in m_arr) {
        if (split(m_arr[i], pair, "=") == 2) {
            dict[pair[1]] = pair[2];
        }
    }
}
{
    if (match($0, /channel="([^"]+)"/, c) && match($0, /start="([0-9]{12})/, s)) {
        old_id = c[1];
        start_key = s[1]; 
        
        if (old_id in dict) {
            new_id = dict[old_id];
            key = new_id "_" start_key;
            
            if (!seen[key]++) {
                line = $0;
                gsub("channel=\"" old_id "\"", "channel=\"" new_id "\"", line);
                sub(/^[ \t\r\n]+/, "", line);
                if (line != "") print line "</programme>";
            }
        }
    }
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# Nettoyage final
rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"

echo "---------------------------------------"
echo "SUCCÈS : ${OUTPUT_FILE}.gz généré."
