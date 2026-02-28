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
LOG_FILE="epg_session.log"

mkdir -p "$TEMP_DIR"
echo "--- Session du $(date) ---" > "$LOG_FILE"

# 1. CHARGEMENT DU MAPPING
declare -A ID_MAP
declare -A SOURCE_TRACKER # Pour le rapport final
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

# PARAMÈTRES TEMPORELS
NOW=$(date +%Y%m%d%H%M)
LIMIT=$(date -d "+1 days" +%Y%m%d%H%M)

echo "--- Démarrage du traitement ---" | tee -a "$LOG_FILE"

# ==============================================================================
# 2. RÉCUPÉRATION ET FILTRAGE (AVEC PRIORITÉ)
# ==============================================================================
declare -A CHANNELS_FILLED
count=0
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [[ -z "$url" ]] && continue

    count=$((count + 1))
    RAW_FILE="$TEMP_DIR/raw_$count.xml"
    SRC_FILE="$TEMP_DIR/src_$count.xml"

    echo "Source $count : $url" | tee -a "$LOG_FILE"
    
    # Téléchargement
    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 15 "$url" | gunzip > "$RAW_FILE" 2>/dev/null
    else
        curl -sL --connect-timeout 15 "$url" > "$RAW_FILE" 2>/dev/null
    fi

    if [[ -s "$RAW_FILE" ]]; then
        ids_in_source=$(xmlstarlet sel -t -v "/tv/channel/@id" "$RAW_FILE" 2>/dev/null)
        xpath_filter=""
        found_count=0

        for old_id in $ids_in_source; do
            new_id=${ID_MAP[$old_id]}
            if [[ -n "$new_id" ]]; then
                # On vérifie si ce NEW_ID a déjà été rempli par une source précédente
                if [[ -z "${CHANNELS_FILLED[$new_id]}" ]]; then
                    xpath_filter+="@id='$old_id' or @channel='$old_id' or "
                    CHANNELS_FILLED["$new_id"]=1
                    SOURCE_TRACKER["$new_id"]="Source $count"
                    ((found_count++))
                fi
            fi
        done

        xpath_filter="${xpath_filter% or }"
        
        if [ $found_count -gt 0 ]; then
            echo "  [OK] +$found_count chaînes récupérées." | tee -a "$LOG_FILE"
            xmlstarlet ed \
                -d "/tv/channel[not($xpath_filter)]" \
                -d "/tv/programme[not($xpath_filter)]" \
                -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
                -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
                "$RAW_FILE" > "$SRC_FILE" 2>/dev/null
        else
            echo "  [i] Aucune nouvelle chaîne pertinente." | tee -a "$LOG_FILE"
            touch "$SRC_FILE"
        fi
        rm -f "$RAW_FILE"
    else
        echo "  [!] Échec du téléchargement ou fichier vide." | tee -a "$LOG_FILE"
    fi
done

# ==============================================================================
# 3. ASSEMBLAGE FINAL
# ==============================================================================
echo "--- Assemblage final ---" | tee -a "$LOG_FILE"

echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# A. Canaux : Extraction et renommage sécurisé
for src in "$TEMP_DIR"/src_*.xml; do
    [[ ! -s "$src" ]] && continue
    
    # On extrait les canaux et on remplace les IDs directement avec sed pour plus de fiabilité
    xmlstarlet sel -t -c "/tv/channel" "$src" 2>/dev/null | sed 's/<\/channel>/<\/channel>\n/g' | while read -r line; do
        [[ -z "$line" ]] && continue
        for old in "${!ID_MAP[@]}"; do
            # Remplacement de l'ID en s'assurant de ne pas toucher au texte des balises
            line="${line//id=\"$old\"/id=\"${ID_MAP[$old]}\"}"
        done
        # On s'assure que la ligne finit bien par un saut de ligne et est fermée
        echo "$line" >> "$OUTPUT_FILE"
    done
done
# Programmes (AWK avec logs internes)
xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/src_*.xml 2>/dev/null | \
awk -v mapping="$(for old in "${!ID_MAP[@]}"; do printf "%s=%s;" "$old" "${ID_MAP[$old]}"; done)" '
BEGIN { 
    RS="</programme>"; 
    n=split(mapping,m,";"); 
    for(i=1;i<=n;i++){
        split(m[i],p,"="); 
        if(p[1]) dict[p[1]]=p[2]
    } 
}
{
    line = $0;
    if (match(line, /channel="([^"]+)"/, c) && match(line, /start="([0-9]{12})/, s)) {
        old_id = c[1];
        start_k = s[1];
        if (old_id in dict) {
            new_id = dict[old_id];
            gsub("channel=\"" old_id "\"", "channel=\"" new_id "\"", line);
            if (!seen[new_id "_" start_k]++) {
                sub(/^[ \t\r\n]+/, "", line);
                if (length(line) > 0) print line "</programme>"
            }
        }
    }
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# ==============================================================================
# 4. RAPPORT FINAL
# ==============================================================================
echo "" | tee -a "$LOG_FILE"
echo "=== RÉCAPITULATIF DU MAPPING ===" | tee -a "$LOG_FILE"
printf "%-30s | %-30s | %-15s\n" "ID Original" "Nouvel ID" "Status" | tee -a "$LOG_FILE"
echo "--------------------------------------------------------------------------------" | tee -a "$LOG_FILE"

for old in "${CHANNEL_IDS[@]}"; do
    new="${ID_MAP[$old]}"
    status="${SOURCE_TRACKER[$new]:-NON TROUVÉ}"
    printf "%-30s | %-30s | %-15s\n" "$old" "$new" "$status" | tee -a "$LOG_FILE"
done

# Nettoyage
rm -rf "$TEMP_DIR"
echo "--------------------------------------------------------------------------------"
echo "SUCCÈS : ${OUTPUT_FILE} généré." | tee -a "$LOG_FILE"
echo "Logs disponibles dans : $LOG_FILE"
