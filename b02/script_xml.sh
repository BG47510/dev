#!/bin/bash

cd "$(dirname "$0")" || exit 1

# CONFIGURATION
CHANNELS_FILE="channels.txt"
URLS_FILE="urls.txt"
OUTPUT_FILE="epg.xml"
TEMP_DIR="./temp_epg"

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
NOW=$(date +%Y%m%d%H%M)
LIMIT=$(date -d "+1 days" +%Y%m%d%H%M)

# Construction des filtres XPath basés sur les IDs d'origine
xpath_channels=""
xpath_progs=""
for id in "${CHANNEL_IDS[@]}"; do
    xpath_channels+="@id='$id' or "
    xpath_progs+="@channel='$id' or "
done
xpath_channels="${xpath_channels% or }"
xpath_progs="${xpath_progs% or }"

echo "--- Démarrage ---"

# 2. RÉCUPÉRATION ET FILTRAGE
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

count=0
for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [[ -z "$url" ]] && continue
    count=$((count + 1))
    RAW_FILE="$TEMP_DIR/raw_$count.xml"
    
    curl -sL --connect-timeout 10 --fail "$url" | ( [[ "$url" == *.gz ]] && gunzip || cat ) > "$RAW_FILE" 2>/dev/null

    if [[ -s "$RAW_FILE" ]]; then
        xmlstarlet ed \
            -d "/tv/channel[not($xpath_channels)]" \
            -d "/tv/programme[not($xpath_progs)]" \
            -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
            -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
            "$RAW_FILE" > "$TEMP_DIR/src_$count.xml" 2>/dev/null
        rm -f "$RAW_FILE"
    fi
done

# 3. FUSION ET DÉDOUBLONNAGE
echo "Traitement final..."
echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# A. CHANNELS : Ici on RENOMME l'ID selon votre mapping
for old_id in "${!ID_MAP[@]}"; do
    new_id=${ID_MAP[$old_id]}
    xmlstarlet sel -t -c "/tv/channel[@id='$old_id']" "$TEMP_DIR"/*.xml 2>/dev/null | \
    sed "s/id=\"$old_id\"/id=\"$new_id\"/g" | \
    awk '!x[$0]++' >> "$OUTPUT_FILE"
done

# B. PROGRAMMES : On garde l'ID d'origine dans le XML, mais on dédouble
# On passe le mapping à AWK uniquement pour "calculer" la clé de dédoublonnage
xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/*.xml 2>/dev/null | \
awk -v mapping="$(for old in "${!ID_MAP[@]}"; do printf "%s=%s;" "$old" "${ID_MAP[$old]}"; done)" '
BEGIN { 
    RS="</programme>"; 
    n = split(mapping, a, ";");
    for (i=1; i<=n; i++) {
        split(a[i], pair, "=");
        if (pair[1]) map[pair[1]] = pair[2];
    }
}
{
    if (match($0, /channel="([^"]+)"/, c) && match($0, /start="([^"]+)"/, s)) {
        old_id = c[1];
        start_val = substr(s[1], 1, 12);
        
        # On ne garde que si l ID est dans notre liste
        if (old_id in map) {
            # CLÉ DE DÉDOUBLONNAGE : On utilise le NOUVEL ID (mapping) + DATE
            # pour que "M6.fr" et "M6.com" soient vus comme la même entité
            key = map[old_id] "_" start_val;
            
            if (!seen[key]++) {
                # On imprime le bloc SANS RIEN MODIFIER (on garde channel="M6test" etc.)
                sub(/^[ \t\r\n]+/, "", $0);
                print $0 "</programme>"
            }
        }
    }
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"
echo "TERMINÉ."
