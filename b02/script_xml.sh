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
MAP_AWK=""

while IFS=',' read -r old_id new_id || [[ -n "$old_id" ]]; do
    [[ "$old_id" =~ ^\s*(#|$) ]] && continue
    old_clean=$(echo "$old_id" | tr -d '\r' | xargs)
    new_clean=$(echo "$new_id" | tr -d '\r' | xargs)
    
    if [[ -n "$old_clean" && -n "$new_clean" ]]; then
        ID_MAP["$old_clean"]="$new_clean"
        MAP_AWK+="${old_clean}=${new_clean};"
    fi
done < "$CHANNELS_FILE"

# Construction des filtres XPath
xpath_channels=""
xpath_progs=""
for id in "${!ID_MAP[@]}"; do
    xpath_channels+="@id='$id' or "
    xpath_progs+="@channel='$id' or "
done
xpath_channels="${xpath_channels% or }"
xpath_progs="${xpath_progs% or }"

echo "--- Récupération et Normalisation ---"

# ==============================================================================
# 2. RÉCUPÉRATION ET EXTRACTION
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
        curl -sL --connect-timeout 10 --fail "$url" | gunzip > "$RAW_FILE" 2>/dev/null
    else
        curl -sL --connect-timeout 10 --fail "$url" > "$RAW_FILE" 2>/dev/null
    fi

    if [[ -s "$RAW_FILE" ]]; then
        # Extraction et mise à plat : chaque bloc devient UNE ligne
        xmlstarlet sel -t -c "/tv/channel[$xpath_channels]" "$RAW_FILE" | sed 's|</channel>|</channel>\n|g' >> "$TEMP_DIR/all_chans.tmp" 2>/dev/null
        xmlstarlet sel -t -c "/tv/programme[$xpath_progs]" "$RAW_FILE" | sed 's|</programme>|</programme>\n|g' >> "$TEMP_DIR/all_progs.tmp" 2>/dev/null
    fi
    rm -f "$RAW_FILE"
done

# ==============================================================================
# 3. TRAITEMENT ET DÉDOUBLONNAGE (LOGIQUE LIGNE PAR LIGNE)
# ==============================================================================
echo "Traitement final..."

echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# --- A. CHANNELS ---
if [[ -f "$TEMP_DIR/all_chans.tmp" ]]; then
    awk -v mapping="$MAP_AWK" '
    BEGIN { split(mapping, m, ";"); for (i in m) { split(m[i], p, "="); if(p[1]) dict[p[1]]=p[2] } }
    {
        if (match($0, /id="([^"]+)"/, a)) {
            new_id = dict[a[1]];
            if (new_id && !seen[new_id]++) {
                line = $0;
                gsub("id=\"" a[1] "\"", "id=\"" new_id "\"", line);
                print line;
            }
        }
    }' "$TEMP_DIR/all_chans.tmp" >> "$OUTPUT_FILE"
fi

# --- B. PROGRAMMES ---
if [[ -f "$TEMP_DIR/all_progs.tmp" ]]; then
    # Ici on ne change plus le RS, on traite ligne par ligne (grâce au sed plus haut)
    awk -v mapping="$MAP_AWK" '
    BEGIN { split(mapping, m, ";"); for (i in m) { split(m[i], p, "="); if(p[1]) dict[p[1]]=p[2] } }
    {
        # Extraction de l ID et des 12 chiffres du start
        id_ok = match($0, /channel="([^"]+)"/, c);
        time_ok = match($0, /start="([0-9]{12})/, t);

        if (id_ok && time_ok) {
            old_id = c[1];
            new_id = dict[old_id];
            time_key = t[1];
            
            # Clé unique : ID final + HEURE
            key = new_id "_" time_key;
            
            if (new_id && !seen[key]++) {
                line = $0;
                # Remplacement sécurisé de l attribut channel
                gsub("channel=\"" old_id "\"", "channel=\"" new_id "\"", line);
                print line;
            }
        }
    }' "$TEMP_DIR/all_progs.tmp" >> "$OUTPUT_FILE"
fi

echo '</tv>' >> "$OUTPUT_FILE"

# Nettoyage et compression
rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"

echo "---------------------------------------"
echo "SUCCÈS : ${OUTPUT_FILE}.gz généré."
