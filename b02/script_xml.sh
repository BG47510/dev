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

echo "--- Récupération et filtrage ---"

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
    
    # Téléchargement et extraction immédiate des blocs bruts
    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 10 --fail "$url" | gunzip > "$TEMP_DIR/raw.xml"
    else
        curl -sL --connect-timeout 10 --fail "$url" > "$TEMP_DIR/raw.xml"
    fi

    if [[ -s "$TEMP_DIR/raw.xml" ]]; then
        # On extrait les balises complètes sans transformation pour l instant
        xmlstarlet sel -t -c "/tv/channel[$xpath_channels]" "$TEMP_DIR/raw.xml" >> "$TEMP_DIR/all_chans.tmp" 2>/dev/null
        xmlstarlet sel -t -c "/tv/programme[$xpath_progs]" "$TEMP_DIR/raw.xml" >> "$TEMP_DIR/all_progs.tmp" 2>/dev/null
    fi
    rm -f "$TEMP_DIR/raw.xml"
done

# ==============================================================================
# 3. TRAITEMENT ET DÉDOUBLONNAGE (LOGIQUE ROBUSTE)
# ==============================================================================
echo "Traitement final..."

echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# --- A. CHANNELS ---
if [[ -f "$TEMP_DIR/all_chans.tmp" ]]; then
    # On utilise RS='>' pour traiter balise par balise
    awk -v mapping="$MAP_AWK" '
    BEGIN { 
        RS="</channel>"; 
        split(mapping, m, ";"); for (i in m) { split(m[i], p, "="); if(p[1]) dict[p[1]]=p[2] } 
    }
    {
        if (match($0, /id="([^"]+)"/, a)) {
            old_id = a[1];
            new_id = dict[old_id];
            if (new_id && !seen[new_id]++) {
                sub(/id="[^"]+"/, "id=\"" new_id "\"", $0);
                print $0 "</channel>";
            }
        }
    }' "$TEMP_DIR/all_chans.tmp" >> "$OUTPUT_FILE"
fi

# --- B. PROGRAMMES ---
if [[ -f "$TEMP_DIR/all_progs.tmp" ]]; then
    awk -v mapping="$MAP_AWK" '
    BEGIN { 
        RS="</programme>"; 
        split(mapping, m, ";"); for (i in m) { split(m[i], p, "="); if(p[1]) dict[p[1]]=p[2] } 
    }
    {
        # Extraction de l ID et de l heure (12 premiers chiffres de start)
        # On utilise une regex qui cherche les chiffres n importe où après start="
        id_match = match($0, /channel="([^"]+)"/, c);
        time_match = match($0, /start="[^0-9]*([0-9]{12})/, t);

        if (id_match && time_match) {
            old_id = c[1];
            time_key = t[1];
            new_id = dict[old_id];
            
            if (new_id) {
                # LA CLÉ DE DÉDOUBLONNAGE
                key = new_id "_" time_key;
                
                if (!seen[key]++) {
                    # Remplacement de l ID
                    sub(/channel="[^"]+"/, "channel=\"" new_id "\"", $0);
                    # Nettoyage des sauts de ligne en tête pour éviter les trous
                    sub(/^[ \t\r\n]+/, "", $0);
                    if (length($0) > 5) print $0 "</programme>";
                }
            }
        }
    }' "$TEMP_DIR/all_progs.tmp" >> "$OUTPUT_FILE"
fi

echo '</tv>' >> "$OUTPUT_FILE"

# Nettoyage et compression
rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"

echo "---------------------------------------"
echo "TERMINÉ : ${OUTPUT_FILE}.gz créé."
