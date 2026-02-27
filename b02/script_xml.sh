#!/bin/bash

cd "$(dirname "$0")" || exit 1

# --- CONFIGURATION ---
CHANNELS_FILE="channels.txt"
URLS_FILE="urls.txt"
OUTPUT_FILE="epg.xml"
TEMP_DIR="./temp_epg"
DATA_EXTRACT="$TEMP_DIR/extracted_data.txt"

mkdir -p "$TEMP_DIR"
rm -f "$DATA_EXTRACT"

# 1. CHARGEMENT DU MAPPING
declare -A ID_MAP
while IFS=',' read -r old_id new_id || [[ -n "$old_id" ]]; do
    [[ "$old_id" =~ ^\s*(#|$) ]] && continue
    old_clean=$(echo "$old_id" | tr -d '\r' | xargs)
    new_clean=$(echo "$new_id" | tr -d '\r' | xargs)
    [[ -n "$old_clean" && -n "$new_clean" ]] && ID_MAP["$old_clean"]="$new_clean"
done < "$CHANNELS_FILE"

NOW=$(date +%Y%m%d%H%M)
LIMIT=$(date -d "+2 days" +%Y%m%d%H%M)

# 2. EXTRACTION ET NORMALISATION
echo "--- Extraction des sources ---"
count=0
while read -r url || [[ -n "$url" ]]; do
    [[ "$url" =~ ^\s*(#|$) || -z "$url" ]] && continue
    count=$((count + 1))
    echo "Source $count : $url"
    
    RAW="$TEMP_DIR/raw_$count.xml"
    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 10 "$url" | gunzip > "$RAW" 2>/dev/null
    else
        curl -sL --connect-timeout 10 "$url" > "$RAW" 2>/dev/null
    fi

    if [[ -s "$RAW" ]]; then
        # On extrait les infos : ID_SOURCE | START | STOP | TITRE (ou bloc entier)
        # On utilise une astuce xmlstarlet pour sortir chaque programme sur une seule ligne
        xmlstarlet sel -t -m "/tv/programme" \
            -v "../channel[@id=current()/@channel]/display-name" -o "||" \
            -v "@channel" -o "||" \
            -v "@start" -o "||" \
            -v "@stop" -o "||" \
            -c "." -n "$RAW" 2>/dev/null >> "$DATA_EXTRACT"
    fi
    rm -f "$RAW"
done < "$URLS_FILE"

# 3. RECONSTRUCTION DU XML
echo "--- Reconstruction et Dédoublonnage ---"
echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# A. Les chaînes (On les recrée proprement pour éviter les balises orphelines)
declare -A DONE_CHANNELS
for old in "${!ID_MAP[@]}"; do
    new="${ID_MAP[$old]}"
    if [[ -z "${DONE_CHANNELS[$new]}" ]]; then
        echo "  <channel id=\"$new\"><display-name>$new</display-name></channel>" >> "$OUTPUT_FILE"
        DONE_CHANNELS["$new"]=1
    fi
done

# B. Les programmes
# On utilise AWK pour dédoublonner sur (ID_CIBLE + 12 premiers chiffres du START)
awk -F "||" -v mapping="$(for old in "${!ID_MAP[@]}"; do printf "%s=%s;" "$old" "${ID_MAP[$old]}"; done)" '
BEGIN {
    split(mapping, m_array, ";");
    for (i in m_array) {
        split(m_array[i], pair, "=");
        if (pair[1]) dict[pair[1]] = pair[2];
    }
}
{
    old_id = $2;
    start_full = $3;
    stop_full = $4;
    xml_content = $5;
    
    if (old_id in dict) {
        new_id = dict[old_id];
        # On normalise la clé sur les 12 premiers chiffres de la date (YYYYMMDDHHMM)
        key = new_id "_" substr(start_full, 1, 12);
        
        if (!seen[key]++) {
            # On nettoie le bloc XML pour s assurer qu il est complet
            # On remplace l ID et on s assure que la balise est fermée
            gsub("channel=\"" old_id "\"", "channel=\"" new_id "\"", xml_content);
            if (xml_content ~ /<programme/ && xml_content !~ /<\/programme>/) {
                xml_content = xml_content "</programme>";
            }
            print xml_content;
        }
    }
}' "$DATA_EXTRACT" >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# 4. NETTOYAGE
# Suppression des doublons de balises mal formées si xmlstarlet a été trop zélé
sed -i '/<\/programme><\/programme>/s//<\/programme>/g' "$OUTPUT_FILE"

rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"
echo "Succès : ${OUTPUT_FILE}.gz"
