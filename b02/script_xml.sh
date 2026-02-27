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

# 1. CHARGEMENT DU MAPPING (old_id -> new_id)
declare -A ID_MAP
while IFS=',' read -r old_id new_id || [[ -n "$old_id" ]]; do
    [[ "$old_id" =~ ^\s*(#|$) ]] && continue
    old_clean=$(echo "$old_id" | tr -d '\r' | xargs)
    new_clean=$(echo "$new_id" | tr -d '\r' | xargs)
    [[ -n "$old_clean" && -n "$new_clean" ]] && ID_MAP["$old_clean"]="$new_clean"
done < "$CHANNELS_FILE"

# PARAMÈTRES TEMPORELS
NOW=$(date +%Y%m%d%H%M)
LIMIT=$(date -d "+1 days" +%Y%m%d%H%M)

echo "--- Démarrage : $(date) ---"

# ==============================================================================
# 2. RÉCUPÉRATION ET NORMALISATION (Extraction structurée)
# ==============================================================================
count=0
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [[ -z "$url" ]] && continue
    count=$((count + 1))
    
    RAW_FILE="$TEMP_DIR/raw_$count.xml"
    echo "Source $count : $url"

    # Téléchargement
    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 10 --fail "$url" | gunzip > "$RAW_FILE" 2>/dev/null
    else
        curl -sL --connect-timeout 10 --fail "$url" > "$RAW_FILE" 2>/dev/null
    fi

    if [[ -s "$RAW_FILE" ]]; then
        # A. Extraire les balises <channel>
        xmlstarlet sel -t -c "/tv/channel" "$RAW_FILE" > "$TEMP_DIR/ch_$count.xml" 2>/dev/null
        
        # B. Extraire les programmes en format plat : ID|START|STOP|XML_CONTENT
        # On ajoute le filtrage temporel ici pour ne pas charger inutilement la suite
        xmlstarlet sel -t -m "/tv/programme[substring(@stop,1,12) >= '$NOW' and substring(@start,1,12) <= '$LIMIT']" \
            -v "@channel" -o "|" -v "@start" -o "|" -c "." -n \
            "$RAW_FILE" > "$TEMP_DIR/pg_$count.txt" 2>/dev/null
        
        rm -f "$RAW_FILE"
    else
        echo "  [!] Erreur de téléchargement ou fichier vide."
    fi
done

# ==============================================================================
# 3. ASSEMBLAGE ET FUSION (Dédoublonnage intelligent)
# ==============================================================================
echo "Assemblage et fusion des programmes..."
echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# A. Canaux : Dédoublonnage par ID cible
declare -A DONE_CHANNELS
for f in "$TEMP_DIR"/ch_*.xml; do
    [ ! -f "$f" ] && continue
    while read -r line; do
        if [[ "$line" =~ id=\"([^\"]+)\" ]]; then
            old_id="${BASH_REMATCH[1]}"
            new_id="${ID_MAP[$old_id]}"
            if [[ -n "$new_id" && -z "${DONE_CHANNELS[$new_id]}" ]]; then
                # Remplacement de l'ID et nettoyage du display-name si besoin
                echo "${line//id=\"$old_id\"/id=\"$new_id\"}" >> "$OUTPUT_FILE"
                DONE_CHANNELS["$new_id"]=1
            fi
        fi
    done < "$f"
done

# B. Programmes : Fusion par "ID_CIBLE + START_TIME"
# On utilise AWK pour traiter la masse de données avec le mapping en mémoire
cat "$TEMP_DIR"/pg_*.txt 2>/dev/null | awk -F'|' -v mapping="$(for old in "${!ID_MAP[@]}"; do printf "%s=%s;" "$old" "${ID_MAP[$old]}"; done)" '
BEGIN {
    n = split(mapping, m_array, ";");
    for (i=1; i<=n; i++) {
        split(m_array[i], pair, "=");
        if (pair[1]) dict[pair[1]] = pair[2];
    }
}
{
    old_id = $1; start_time = $2; xml_block = $3;
    if (old_id in dict) {
        new_id = dict[old_id];
        key = new_id "_" start_time;
        if (!seen[key]++) {
            # Remplace l ID source par l ID cible proprement
            gsub("channel=\"" old_id "\"", "channel=\"" new_id "\"", xml_block);
            # Nettoyage des sauts de ligne inutiles pour compacter
            sub(/^[ \t\r\n]+/, "", xml_block);
            print xml_block;
        }
    }
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# ==============================================================================
# NETTOYAGE
# ==============================================================================
rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"

echo "---"
echo "SUCCÈS : ${OUTPUT_FILE}.gz généré."
echo "Chaînes uniques intégrées : ${#DONE_CHANNELS[@]}"
