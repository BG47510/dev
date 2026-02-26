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

# Construction du filtre de sélection (on ne garde que nos IDs)
xpath_filter=""
for id in "${CHANNEL_IDS[@]}"; do
    xpath_filter+="@id='$id' or @channel='$id' or "
done
xpath_filter="${xpath_filter% or }"

mkdir -p "$TEMP_DIR"
NOW=$(date +%Y%m%d%H%M)

# 2. RÉCUPÉRATION ET FILTRAGE DRACONIEN
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

count=0
for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [[ -z "$url" ]] && continue
    count=$((count + 1))
    echo "Source $count : $url"
    RAW_FILE="$TEMP_DIR/raw_$count.xml"
    
    curl -sL --connect-timeout 10 --fail "$url" | ( [[ "$url" == *.gz ]] && gunzip || cat ) > "$RAW_FILE"

    if [[ -s "$RAW_FILE" ]]; then
        # ÉTAPE A : On extrait UNIQUEMENT ce qui nous intéresse (Filtrage strict)
        # On supprime tout ce qui n'est pas dans notre liste d'IDs d'origine
        xmlstarlet ed \
            -d "/tv/channel[not($xpath_filter)]" \
            -d "/tv/programme[not($xpath_filter)]" \
            -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
            "$RAW_FILE" > "$TEMP_DIR/filtered_$count.xml" 2>/dev/null
        
        # ÉTAPE B : Renommage des IDs dans le fichier filtré
        # On utilise une boucle plus simple pour éviter de saturer xmlstarlet
        cp "$TEMP_DIR/filtered_$count.xml" "$TEMP_DIR/src_$count.xml"
        for old in "${!ID_MAP[@]}"; do
            new="${ID_MAP[$old]}"
            # On remplace l'ID de la chaîne et le channel du programme
            sed -i "s/id=\"$old\"/id=\"$new\"/g" "$TEMP_DIR/src_$count.xml"
            sed -i "s/channel=\"$old\"/channel=\"$new\"/g" "$TEMP_DIR/src_$count.xml"
        done
        rm -f "$RAW_FILE" "$TEMP_DIR/filtered_$count.xml"
    fi
done

# 3. FUSION ET DÉDOUBLONNAGE
echo "Fusion et suppression des doublons..."
echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# CHANNELS (Uniques)
xmlstarlet sel -t -c "/tv/channel" "$TEMP_DIR"/src_*.xml 2>/dev/null | \
awk 'RS="</channel>" { if (match($0, /id="([^"]+)"/, m)) { if (!seen[m[1]]++) print $0 "</channel>" } }' >> "$OUTPUT_FILE"

# PROGRAMMES (Uniques par ID + HEURE)
xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/src_*.xml 2>/dev/null | \
awk 'RS="</programme>" {
    c_val=""; s_val="";
    if (match($0, /channel="([^"]+)"/, c)) c_val = c[1];
    if (match($0, /start="([^"]+)"/, s)) s_val = s[1];
    key = c_val substr(s_val, 1, 12);
    if (c_val != "" && !seen[key]++) print $0 "</programme>"
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# NETTOYAGE
rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"
echo "TERMINÉ : ${OUTPUT_FILE}.gz généré."
