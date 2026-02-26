#!/bin/bash

cd "$(dirname "$0")" || exit 1

# CONFIGURATION
CHANNELS_FILE="channels.txt"
URLS_FILE="urls.txt"
OUTPUT_FILE="epg.xml"
TEMP_DIR="./temp_epg"

# Vérification
for f in "$CHANNELS_FILE" "$URLS_FILE"; do
    [[ ! -f "$f" ]] && echo "Erreur : $f introuvable." && exit 1
done

# 1. CHARGEMENT DU MAPPING
declare -A ID_MAP
while IFS=',' read -r old_id new_id || [[ -n "$old_id" ]]; do
    [[ "$old_id" =~ ^\s*(#|$) ]] && continue
    old_clean=$(echo "$old_id" | tr -d '\r' | xargs)
    new_clean=$(echo "$new_id" | tr -d '\r' | xargs)
    [[ -n "$old_clean" && -n "$new_clean" ]] && ID_MAP["$old_clean"]="$new_clean"
done < "$CHANNELS_FILE"

mkdir -p "$TEMP_DIR"
NOW=$(date +%Y%m%d%H%M)
LIMIT=$(date -d "+1 days" +%Y%m%d%H%M)

# 2. RÉCUPÉRATION ET FILTRAGE
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

count=0
for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [[ -z "$url" ]] && continue
    count=$((count + 1))
    echo "Source $count : $url"
    RAW_FILE="$TEMP_DIR/raw_$count.xml"
    
    # Download
    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 10 --fail "$url" | gunzip > "$RAW_FILE" 2>/dev/null
    else
        curl -sL --connect-timeout 10 --fail "$url" > "$RAW_FILE" 2>/dev/null
    fi

    if [[ -s "$RAW_FILE" ]]; then
        # Filtrage et renommage direct des IDs par source pour gagner du temps
        # On crée une commande XMLStarlet dynamique pour cette source
        ED_CMD=("xmlstarlet" "ed")
        for old in "${!ID_MAP[@]}"; do
            new="${ID_MAP[$old]}"
            ED_CMD+=("-u" "/tv/channel[@id='$old']/@id" "-v" "$new")
            ED_CMD+=("-u" "/tv/programme[@channel='$old']/@channel" "-v" "$new")
        done
        
        # On supprime aussi ce qui n'est pas mappé et hors limites
        "${ED_CMD[@]}" \
            -d "/tv/channel[not(string-length(@id) > 0)]" \
            -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
            -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
            "$RAW_FILE" > "$TEMP_DIR/src_$count.xml" 2>/dev/null
        
        rm -f "$RAW_FILE"
    fi
done

# 3. FUSION ET DÉDOUBLONNAGE FINAL
echo "Fusion et suppression des doublons..."

echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# A. CHANNELS : Uniques par ID
# On récupère tous les <channel>, on les groupe par ID et on prend le premier
xmlstarlet sel -t -c "/tv/channel" "$TEMP_DIR"/*.xml 2>/dev/null | \
awk 'RS="</channel>" { 
    if (match($0, /id="([^"]+)"/, m)) { 
        if (!seen[m[1]]++) print $0 "</channel>" 
    } 
}' >> "$OUTPUT_FILE"

# B. PROGRAMMES : Uniques par [ID + START]
# On utilise une regex plus souple pour capturer start et channel peu importe l'ordre
xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/*.xml 2>/dev/null | \
awk 'RS="</programme>" {
    # Extraction propre des attributs pour la clé unique
    chan = ""; start = "";
    if (match($0, /channel="([^"]+)"/, c)) chan = c[1];
    if (match($0, /start="([^"]+)"/, s)) start = s[1];
    
    # On ne garde que les 12 premiers chiffres de la date pour ignorer les fuseaux (+0100)
    # qui pourraient fausser le dédoublonnage
    key = chan substr(start, 1, 12);
    
    if (chan != "" && !seen[key]++) {
        print $0 "</programme>"
    }
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# NETTOYAGE
rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"
echo "TERMINÉ : ${OUTPUT_FILE}.gz généré."
