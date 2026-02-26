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

# 2. RÉCUPÉRATION ET FILTRAGE
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")
count=0
for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs); [[ -z "$url" ]] && continue
    count=$((count + 1))
    RAW_FILE="$TEMP_DIR/raw_$count.xml"
    curl -sL --max-time 30 --fail "$url" | ( [[ "$url" == *.gz ]] && gunzip || cat ) > "$RAW_FILE" 2>/dev/null

    if [[ -s "$RAW_FILE" ]]; then
        # On filtre les IDs d'origine
        xpath_p=""
        for id in "${CHANNEL_IDS[@]}"; do xpath_p+="@channel='$id' or "; done
        xmlstarlet ed -d "/tv/channel[not(@id='$(echo "${CHANNEL_IDS[@]}" | sed "s/ /' or @id='/g")')]" \
            -d "/tv/programme[not(${xpath_p% or })]" \
            -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
            "$RAW_FILE" > "$TEMP_DIR/src_$count.xml" 2>/dev/null
    fi
    rm -f "$RAW_FILE"
done

# 3. EXTRACTION DES DISPLAY-NAMES ET FUSION
echo "Fusion et renommage vers Display-Name..."
echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# Création d'un mapping ID_ORIGINE -> DISPLAY_NAME
# On cherche le premier <display-name> pour chaque ID traité
declare -A NAME_MAP
for old_id in "${CHANNEL_IDS[@]}"; do
    name=$(xmlstarlet sel -t -v "/tv/channel[@id='$old_id']/display-name[1]" "$TEMP_DIR"/src_*.xml 2>/dev/null | head -n 1)
    [[ -z "$name" ]] && name="$old_id" # Fallback si pas de nom trouvé
    NAME_MAP["$old_id"]="$name"
done

# A. Balises <channel> : ID devient "M6test" (selon channels.txt)
for old_id in "${!ID_MAP[@]}"; do
    new_id=${ID_MAP[$old_id]}
    xmlstarlet sel -t -c "/tv/channel[@id='$old_id']" "$TEMP_DIR"/*.xml 2>/dev/null | \
    sed "s/id=\"$old_id\"/id=\"$new_id\"/g" | awk '!x[$0]++' >> "$OUTPUT_FILE"
done

# B. Balises <programme> : L'attribut channel devient le DISPLAY-NAME (ex: "M6")
# Préparation de la chaîne de mapping pour AWK (old_id=display_name)
prog_map_str=""
for old_id in "${!NAME_MAP[@]}"; do
    prog_map_str+="$old_id=${NAME_MAP[$old_id]};"
done

xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/*.xml 2>/dev/null | \
awk -v mapping="$prog_map_str" '
BEGIN { 
    RS="</programme>"; 
    n = split(mapping, a, ";");
    for (i=1; i<=n; i++) {
        split(a[i], pair, "=");
        if (pair[1]) display_dict[pair[1]] = pair[2];
    }
}
{
    if (match($0, /channel="([^"]+)"/, c) && match($0, /start="([^"]+)"/, s)) {
        old_id = c[1];
        start_key = substr(s[1], 1, 12);
        
        if (old_id in display_dict) {
            target_name = display_dict[old_id];
            line = $0;
            # On remplace l attribut channel par le NOM (M6)
            gsub("channel=\"" old_id "\"", "channel=\"" target_name "\"", line);
            
            # Dédoublonnage sur NOM + HEURE
            key = target_name "_" start_key;
            if (!seen[key]++) {
                sub(/^[ \t\r\n]+/, "", line);
                print line "</programme>"
            }
        }
    }
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"
echo "SUCCÈS."
