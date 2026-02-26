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
for_xpath=""
while IFS=',' read -r old_id new_id || [[ -n "$old_id" ]]; do
    [[ "$old_id" =~ ^\s*(#|$) ]] && continue
    old_clean=$(echo "$old_id" | tr -d '\r' | xargs)
    new_clean=$(echo "$new_id" | tr -d '\r' | xargs)
    if [ -n "$old_clean" ]; then
        ID_MAP["$old_clean"]="$new_clean"
        for_xpath+="@id='$old_clean' or @channel='$old_clean' or "
    fi
done < "$CHANNELS_FILE"
xpath_filter="${for_xpath% or }"

# ==============================================================================
# PARAMÈTRES TEMPORELS (Réintégrés pour la performance)
# ==============================================================================
NOW=$(date +%Y%m%d%H%M)
LIMIT=$(date -d "+1 days" +%Y%m%d%H%M)

echo "--- Filtrage : de $NOW à $LIMIT ---"

# ==============================================================================
# 2. RÉCUPÉRATION ET EXTRACTION CIBLÉE
# ==============================================================================
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [ -z "$url" ] && continue
    
    RAW="$TEMP_DIR/tmp.xml"
    echo "Traitement de : $url"
    
    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 10 --fail "$url" | gunzip > "$RAW" 2>/dev/null
    else
        curl -sL --connect-timeout 10 --fail "$url" > "$RAW" 2>/dev/null
    fi

    if [ -s "$RAW" ]; then
        # On filtre TOUT le fichier d'un coup (Gain de temps énorme)
        # On ne garde que les chaînes/programmes du mapping ET dans la plage horaire
        xmlstarlet ed \
            -d "/tv/channel[not($xpath_filter)]" \
            -d "/tv/programme[not($xpath_filter)]" \
            -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
            -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
            "$RAW" > "$TEMP_DIR/filtered.xml" 2>/dev/null

        # Extraction des CHANNELS vers le tampon
        xmlstarlet sel -t -c "/tv/channel" "$TEMP_DIR/filtered.xml" >> "$TEMP_DIR/chans_raw.tmp" 2>/dev/null
        
        # Extraction des PROGRAMMES vers le tampon (Format normalisé pour dédoublonnage)
        xmlstarlet sel -t -m "/tv/programme" \
            -v "concat(@channel, '|', substring(@start,1,12), '|')" -c "." -n \
            "$TEMP_DIR/filtered.xml" >> "$TEMP_DIR/progs_raw.tmp" 2>/dev/null
    fi
    rm -f "$RAW" "$TEMP_DIR/filtered.xml"
done

# ==============================================================================
# 3. MAPPING ET DÉDOUBLONNAGE FINAL
# ==============================================================================
echo "Fusion et dédoublonnage..."
echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# Préparation de la chaîne de mapping pour AWK
MAP_STR=""
for o in "${!ID_MAP[@]}"; do MAP_STR+="$o=${ID_MAP[$o]};"; done

# --- A. CHANNELS ---
if [ -f "$TEMP_DIR/chans_raw.tmp" ]; then
    sed -i 's|</channel>|</channel>\n|g' "$TEMP_DIR/chans_raw.tmp"
    awk -v map="$MAP_STR" '
    BEGIN { split(map, m, ";"); for (i in m) { split(m[i], p, "="); if(p[1]) dict[p[1]]=p[2] } }
    {
        if (match($0, /id="([^"]+)"/, a)) {
            new_id = dict[a[1]];
            if (new_id && !seen[new_id]++) {
                line = $0; gsub("id=\"" a[1] "\"", "id=\"" new_id "\"", line);
                print line;
            }
        }
    }' "$TEMP_DIR/chans_raw.tmp" >> "$OUTPUT_FILE"
fi

# --- B. PROGRAMMES ---
if [ -f "$TEMP_DIR/progs_raw.tmp" ]; then
    awk -F'|' -v map="$MAP_STR" '
    BEGIN { split(map, m, ";"); for (i in m) { split(m[i], p, "="); if(p[1]) dict[p[1]]=p[2] } }
    $1 != "" {
        old_id = $1;
        new_id = dict[old_id];
        time_key = $2;
        key = new_id "_" time_key;
        
        if (new_id && !seen[key]++) {
            line = $3;
            gsub("channel=\"" old_id "\"", "channel=\"" new_id "\"", line);
            print line;
        }
    }' "$TEMP_DIR/progs_raw.tmp" >> "$OUTPUT_FILE"
fi

echo '</tv>' >> "$OUTPUT_FILE"

# Nettoyage
rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"

echo "SUCCÈS : ${OUTPUT_FILE}.gz généré."
