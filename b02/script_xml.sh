#!/bin/bash

cd "$(dirname "$0")" || exit 1

# --- CONFIGURATION ---
CHANNELS_FILE="channels.txt"
URLS_FILE="urls.txt"
OUTPUT_FILE="epg.xml"
TEMP_DIR="./temp_epg"
mkdir -p "$TEMP_DIR"

# 1. CHARGEMENT DU MAPPING
declare -A ID_MAP
while IFS=',' read -r old_id new_id || [[ -n "$old_id" ]]; do
    [[ "$old_id" =~ ^\s*(#|$) ]] && continue
    old_clean=$(echo "$old_id" | tr -d '\r' | xargs)
    new_clean=$(echo "$new_id" | tr -d '\r' | xargs)
    [[ -n "$old_clean" && -n "$new_clean" ]] && ID_MAP["$old_clean"]="$new_clean"
done < "$CHANNELS_FILE"

NOW=$(date +%Y%m%d%H%M)
LIMIT=$(date -d "+1 days" +%Y%m%d%H%M)

echo "--- Traitement des sources ---"

# 2. TÉLÉCHARGEMENT ET NORMALISATION
count=0
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [[ -z "$url" ]] && continue
    count=$((count + 1))
    
    RAW="$TEMP_DIR/raw_$count.xml"
    SRC="$TEMP_DIR/src_$count.xml"
    echo "Source $count : $url"

    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 10 "$url" | gunzip > "$RAW" 2>/dev/null
    else
        curl -sL --connect-timeout 10 "$url" > "$RAW" 2>/dev/null
    fi

    if [[ -s "$RAW" ]]; then
        # On ne garde que ce qui est dans le mapping et dans la plage horaire
        # On force le renommage des IDs dès maintenant pour faciliter la fusion
        cp "$RAW" "$SRC"
        for old in "${!ID_MAP[@]}"; do
            new="${ID_MAP[$old]}"
            # On utilise sed pour renommer massivement les IDs dans le fichier source
            sed -i "s/id=\"$old\"/id=\"$new\"/g; s/channel=\"$old\"/channel=\"$new\"/g" "$SRC"
        done
        
        # Nettoyage : on supprime tout ce qui n'appartient pas à nos IDs cibles
        xpath_ids=""
        for new in "${ID_MAP[@]}"; do xpath_ids+="@id='$new' or @channel='$new' or "; done
        xpath_ids="${xpath_ids% or }"

        xmlstarlet ed -L \
            -d "/tv/channel[not($xpath_ids)]" \
            -d "/tv/programme[not($xpath_ids)]" \
            -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
            -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
            "$SRC" 2>/dev/null
        
        rm -f "$RAW"
    fi
done

# 3. ASSEMBLAGE FINAL (Le coeur du dédoublonnage)
echo "Fusion et dédoublonnage final..."
echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# A. Canaux (Unique par ID)
cat "$TEMP_DIR"/src_*.xml | xmlstarlet sel -t -c "/tv/channel" 2>/dev/null | \
awk '!seen[$0]++' >> "$OUTPUT_FILE"

# B. Programmes (Unique par ID + START)
# On normalise la clé de temps (12 premiers chiffres) pour ignorer les différences de format +0100
cat "$TEMP_DIR"/src_*.xml | xmlstarlet sel -t -m "/tv/programme" -v "@channel" -o "|" -v "substring(@start,1,12)" -o "|" -c "." -n 2>/dev/null | \
awk -F'|' '{
    key = $1 "_" $2;
    if (!seen[key]++) {
        print $3;
    }
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# Nettoyage
rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"
echo "Terminé : ${OUTPUT_FILE}.gz"
