#!/bin/bash
# ==============================================================================
# Version 1.2 - Correction des filtres XPath et robustesse
# ==============================================================================

set -e
cd "$(dirname "$0")" || exit 1

# CONFIGURATION
CHANNELS_FILE="channels.txt"
URLS_FILE="urls.txt"
OUTPUT_FILE="filtered_epg.xml"
TEMP_DIR="./temp_epg"

# Vérification
for f in "$CHANNELS_FILE" "$URLS_FILE"; do
    [[ ! -f "$f" ]] && echo "Erreur : $f introuvable." && exit 1
done

rm -rf "$TEMP_DIR" && mkdir -p "$TEMP_DIR"

# Nettoyage des IDs pour le filtre (Format: ,ID1,ID2,ID3,)
CHANNEL_LIST=$(grep -vE '^\s*(#|$)' "$CHANNELS_FILE" | sed 's/[[:space:]]//g' | paste -sd "," -)
CHANNEL_LIST=",$CHANNEL_LIST,"

mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE" | sed 's/[[:space:]]//g')

# TEMPS (Format XMLTV : YYYYMMDDHHMM)
NOW=$(date +%Y%m%d%H%M)
LIMIT=$(date -d "+3 days" +%Y%m%d%H%M) # Attention: spécifique GNU Date

echo "--- Démarrage (${#URLS[@]} sources) ---"

count=0
for url in "${URLS[@]}"; do
    count=$((count + 1))
    echo "[$count/${#URLS[@]}] Téléchargement : $url"
    
    RAW_FILE="$TEMP_DIR/raw_$count.xml"
    FILTERED_FILE="$TEMP_DIR/src_$count.xml"

    # Download
    curl -sL --connect-timeout 15 --max-time 120 --fail "$url" | \
    { [[ "$url" == *.gz ]] && gunzip || cat; } > "$RAW_FILE" || true

    if [[ -s "$RAW_FILE" ]]; then
        # Filtrage : On supprime ce qui n'est PAS dans la liste ou hors temps
        # Utilisation de --var pour injecter proprement les variables shell dans XPath
        xmlstarlet ed \
            --var "list" "'$CHANNEL_LIST'" \
            --var "now" "'$NOW'" \
            --var "limit" "'$LIMIT'" \
            -d "/tv/channel[not(contains(\$list, concat(',', @id, ',')))]" \
            -d "/tv/programme[not(contains(\$list, concat(',', @channel, ',')))]" \
            -d "/tv/programme[substring(@stop,1,12) < \$now]" \
            -d "/tv/programme[substring(@start,1,12) > \$limit]" \
            "$RAW_FILE" > "$FILTERED_FILE" 2>/dev/null || echo "Erreur XML source $count"
        
        rm -f "$RAW_FILE"
    fi
done

# FUSION (La logique AWK originale est conservée car efficace pour le stream)
echo "Fusion et dédoublonnage..."
echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# Chaînes
xmlstarlet sel -t -c "/tv/channel" "$TEMP_DIR"/src_*.xml 2>/dev/null | \
    awk -F'id="' 'NF>1{split($2,a,"\""); if(!seen[a[1]]++) print $0}' >> "$OUTPUT_FILE"

# Programmes
xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/src_*.xml 2>/dev/null | \
    awk 'BEGIN { RS="</programme>"; ORS="" } 
    match($0, /channel="([^"]+)"/, c) && match($0, /start="([^"]+)"/, s) {
        key = c[1] "_" s[1]; if (!seen[key]++) print $0 "</programme>"
    }' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"
gzip -f "$OUTPUT_FILE"
echo "Succès : ${OUTPUT_FILE}.gz généré."
