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

mkdir -p "$TEMP_DIR"

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

echo "--- Récupération des sources ---"

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
        # Extraction stricte par xmlstarlet
        xmlstarlet sel -t -c "/tv/channel[$xpath_channels]" "$RAW_FILE" > "$TEMP_DIR/chan_$count.xml" 2>/dev/null
        xmlstarlet sel -t -c "/tv/programme[$xpath_progs]" "$RAW_FILE" > "$TEMP_DIR/prog_$count.xml" 2>/dev/null
        rm -f "$RAW_FILE"
    fi
done

# ==============================================================================
# 3. FUSION ET DÉDOUBLONNAGE
# ==============================================================================
echo "Fusion et dédoublonnage..."

echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# --- A. CHANNELS ---
# On utilise AWK pour changer l'ID et dédoublonner sur le nouvel ID
cat "$TEMP_DIR"/chan_*.xml 2>/dev/null | awk -v mapping="$(for old in "${!ID_MAP[@]}"; do printf "%s=%s;" "$old" "${ID_MAP[$old]}"; done)" '
BEGIN { RS="</channel>"; split(mapping, m, ";"); for (i in m) { split(m[i], p, "="); if(p[1]) dict[p[1]]=p[2] } }
{
    if (match($0, /id="([^"]+)"/, a)) {
        old_id = a[1];
        if (old_id in dict) {
            new_id = dict[old_id];
            if (!seen[new_id]++) {
                sub(/id="[^"]+"/, "id=\"" new_id "\"", $0);
                print $0 "</channel>";
            }
        }
    }
}' >> "$OUTPUT_FILE"

# --- B. PROGRAMMES ---
# On dédoublonne sur NEW_ID + DATE (12 chiffres)
cat "$TEMP_DIR"/prog_*.xml 2>/dev/null | awk -v mapping="$(for old in "${!ID_MAP[@]}"; do printf "%s=%s;" "$old" "${ID_MAP[$old]}"; done)" '
BEGIN { RS="</programme>"; split(mapping, m, ";"); for (i in m) { split(m[i], p, "="); if(p[1]) dict[p[1]]=p[2] } }
{
    if (match($0, /channel="([^"]+)"/, c) && match($0, /start="([0-9]{12})/, s)) {
        old_id = c[1];
        time_key = s[1];
        if (old_id in dict) {
            new_id = dict[old_id];
            key = new_id "_" time_key;
            if (!seen[key]++) {
                sub(/channel="[^"]+"/, "channel=\"" new_id "\"", $0);
                # Filtrage temporel final
                # On ne garde que si ce n est pas vide
                if (length($0) > 10) print $0 "</programme>";
            }
        }
    }
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# Nettoyage
rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"

echo "SUCCÈS : ${OUTPUT_FILE}.gz généré."
