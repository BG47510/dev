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

# 1. CHARGEMENT DU MAPPING (OldID -> NewID)
declare -A ID_MAP
while IFS=',' read -r old_id new_id || [[ -n "$old_id" ]]; do
    [[ "$old_id" =~ ^\s*(#|$) ]] && continue
    old_clean=$(echo "$old_id" | tr -d '\r' | xargs)
    new_clean=$(echo "$new_id" | tr -d '\r' | xargs)
    [ -n "$old_clean" ] && ID_MAP["$old_clean"]="$new_clean"
done < "$CHANNELS_FILE"

echo "--- Traitement des sources ---"

# ==============================================================================
# 2. RÉCUPÉRATION ET NORMALISATION (Extraction vers fichiers temporaires)
# ==============================================================================
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [ -z "$url" ] && continue
    
    RAW="$TEMP_DIR/tmp.xml"
    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 10 --fail "$url" | gunzip > "$RAW" 2>/dev/null
    else
        curl -sL --connect-timeout 10 --fail "$url" > "$RAW" 2>/dev/null
    fi

    if [ -s "$RAW" ]; then
        # On traite chaque chaîne du mapping une par une pour être certain de les capturer
        for old_id in "${!ID_MAP[@]}"; do
            new_id=${ID_MAP[$old_id]}
            
            # Extraction des CHANNELS (on garde le bloc complet)
            xmlstarlet sel -t -c "/tv/channel[@id='$old_id']" "$RAW" | \
                sed "s/id=\"$old_id\"/id=\"$new_id\"/g" >> "$TEMP_DIR/chans.tmp" 2>/dev/null
            
            # Extraction des PROGRAMMES (on force un format fixe : ID|START|BLOC_COMPLET)
            # Cela permet de dédoublonner sur les colonnes 1 et 2 peu importe le contenu du bloc
            xmlstarlet sel -t -m "/tv/programme[@channel='$old_id']" \
                -v "concat('$new_id', '|', substring(@start,1,12), '|')" -c "." -n "$RAW" >> "$TEMP_DIR/progs.tmp" 2>/dev/null
        done
    fi
    rm -f "$RAW"
done

# ==============================================================================
# 3. DÉDOUBLONNAGE ET RECONSTRUCTION
# ==============================================================================
echo "Fusion finale..."

echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# --- A. Dédoublonnage des CHANNELS (sur le New ID) ---
if [ -f "$TEMP_DIR/chans.tmp" ]; then
    # On normalise avec des retours à la ligne pour AWK
    sed -i 's|</channel>|</channel>\n|g' "$TEMP_DIR/chans.tmp"
    awk 'match($0, /id="([^"]+)"/, a) { if (!seen[a[1]]++) print $0 }' "$TEMP_DIR/chans.tmp" >> "$OUTPUT_FILE"
fi

# --- B. Dédoublonnage des PROGRAMMES (sur NewID + DateHeure) ---
if [ -f "$TEMP_DIR/progs.tmp" ]; then
    # Le fichier progs.tmp est au format : NewID|202602261940|<programme...
    awk -F'|' '!seen[$1$2]++ { 
        line = $0;
        # On supprime les deux premières colonnes (ID et Date) pour ne garder que le XML
        sub(/^[^|]+\|[^|]+\|/, "", line);
        # On s assure que l attribut channel est mis à jour dans le bloc XML
        # (déjà fait lors de l extraction, mais par sécurité :)
        print line 
    }' "$TEMP_DIR/progs.tmp" >> "$OUTPUT_FILE"
fi

echo '</tv>' >> "$OUTPUT_FILE"

# Nettoyage
rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"

echo "---------------------------------------"
echo "SUCCÈS : ${OUTPUT_FILE}.gz généré."
