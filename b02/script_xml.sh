#!/bin/bash

cd "$(dirname "$0")" || exit 1

# CONFIGURATION
CHANNELS_FILE="channels.txt"
URLS_FILE="urls.txt"
OUTPUT_FILE="epg.xml"
TEMP_DIR="./temp_epg"

# 1. CHARGEMENT DU MAPPING (Tableau associatif)
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

# 2. RÉCUPÉRATION ET TRAITEMENT PAR SOURCE
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
        # On prépare les modifications XMLStarlet : UNIQUEMENT les attributs @id et @channel
        # Cela garantit que <display-name>M6</display-name> ne deviendra JAMAIS <display-name>M6.fr</display-name>
        ED_ARGS=()
        for old in "${!ID_MAP[@]}"; do
            new="${ID_MAP[$old]}"
            ED_ARGS+=("-u" "/tv/channel[@id='$old']/@id" "-v" "$new")
            ED_ARGS+=("-u" "/tv/programme[@channel='$old']/@channel" "-v" "$new")
        done

        # Filtrage temporel + Renommage sélectif
        xmlstarlet ed "${ED_ARGS[@]}" \
            -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
            -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
            "$RAW_FILE" > "$TEMP_DIR/src_$count.xml" 2>/dev/null
        
        rm -f "$RAW_FILE"
    fi
done

# 3. FUSION ET DÉDOUBLONNAGE ROBUSTE
echo "Fusion finale et nettoyage des doublons..."
echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# A. CHANNELS : Unicité sur le NOUVEL ID
# On extrait les channels, on garde le premier trouvé pour chaque ID
xmlstarlet sel -t -c "/tv/channel" "$TEMP_DIR"/*.xml 2>/dev/null | \
awk 'RS="</channel>" {
    if (match($0, /id="([^"]+)"/, m)) {
        id = m[1];
        if (id != "" && !seen_chan[id]++) print $0 "</channel>"
    }
}' >> "$OUTPUT_FILE"

# B. PROGRAMMES : Unicité sur [ID + HEURE_DE_DEBUT]
# La regex [^"]+ permet de capturer la valeur peu importe l'ordre des attributs
xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/*.xml 2>/dev/null | \
awk 'RS="</programme>" {
    chan = ""; start = "";
    if (match($0, /channel="([^"]+)"/, c)) chan = c[1];
    if (match($0, /start="([^"]+)"/, s)) start = s[1];
    
    # On normalise la clé sur les 12 premiers chiffres (YYYYMMDDHHMM)
    # pour ignorer les différences de fuseaux horaires (+0100) lors du dédoublonnage
    key = chan "_" substr(start, 1, 12);
    
    if (chan != "" && !seen_prog[key]++) {
        # On nettoie les espaces éventuels en début de bloc
        sub(/^[ \t\r\n]+/, "", $0);
        print $0 "</programme>"
    }
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# NETTOYAGE
rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"
echo "SUCCÈS : ${OUTPUT_FILE}.gz généré."
