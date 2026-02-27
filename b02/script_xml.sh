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

# Vérification des fichiers de base
for f in "$CHANNELS_FILE" "$URLS_FILE"; do
    if [[ ! -f "$f" ]]; then
        echo "Erreur : Le fichier $f est introuvable."
        exit 1
    fi
done

# 1. CHARGEMENT DU MAPPING (old_id -> new_id)
declare -A ID_MAP
CHANNEL_IDS=()

while IFS=',' read -r old_id new_id || [[ -n "$old_id" ]]; do
    [[ "$old_id" =~ ^\s*(#|$) ]] && continue
    # Nettoyage des caractères invisibles (\r) et espaces
    old_clean=$(echo "$old_id" | tr -d '\r' | xargs)
    new_clean=$(echo "$new_id" | tr -d '\r' | xargs)
    
    if [[ -n "$old_clean" && -n "$new_clean" ]]; then
        ID_MAP["$old_clean"]="$new_clean"
        CHANNEL_IDS+=("$old_clean")
    fi
done < "$CHANNELS_FILE"

mkdir -p "$TEMP_DIR"

# PARAMÈTRES TEMPORELS (Format XMLTV)
NOW=$(date +%Y%m%d%H%M)
LIMIT=$(date -d "+1 days" +%Y%m%d%H%M)

echo "--- Démarrage du traitement ---"

# ==============================================================================
# 2. RÉCUPÉRATION ET FILTRAGE DES SOURCES
# ==============================================================================
count=0
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [[ -z "$url" ]] && continue

    # Construction du filtre XPath pour cette source
    xpath_channels=""
    xpath_progs=""
    for id in "${!ID_MAP[@]}"; do
        xpath_channels+="@id='$id' or "
        xpath_progs+="@channel='$id' or "
    done
    xpath_channels="${xpath_channels% or }"
    xpath_progs="${xpath_progs% or }"

    count=$((count + 1))
    RAW_FILE="$TEMP_DIR/raw_$count.xml"
    SRC_FILE="$TEMP_DIR/src_$count.xml"

    echo "Source $count : $url"
    
    # Téléchargement (supporte .gz)
    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 10 --fail "$url" | gunzip > "$RAW_FILE" 2>/dev/null
    else
        curl -sL --connect-timeout 10 --fail "$url" > "$RAW_FILE" 2>/dev/null
    fi

    if [[ -s "$RAW_FILE" ]]; then
        # Filtrage strict des IDs et de la plage horaire
        xmlstarlet ed \
            -d "/tv/channel[not($xpath_channels)]" \
            -d "/tv/programme[not($xpath_progs)]" \
            -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
            -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
            "$RAW_FILE" > "$SRC_FILE" 2>/dev/null
        
        rm -f "$RAW_FILE"
    else
        echo "  [!] Erreur ou fichier vide."
    fi
done

# ==============================================================================
# 3. ASSEMBLAGE FINAL
# ==============================================================================
echo "Assemblage du fichier final..."
echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

declare -A WRITTEN_CHANNELS

# A. Extraction des balises <channel> (Dédoublonnage par ID de destination)
for src in "$TEMP_DIR"/src_*.xml; do
    [[ ! -f "$src" ]] && continue
    
    ids_found=$(xmlstarlet sel -t -v "/tv/channel/@id" "$src" 2>/dev/null)
    
    for old_id in $ids_found; do
        new_id=${ID_MAP[$old_id]}
        if [[ -n "$new_id" && -z "${WRITTEN_CHANNELS[$new_id]}" ]]; then
            # On extrait le bloc, on remplace l'ID source par l'ID cible
            xmlstarlet sel -t -c "/tv/channel[@id='$old_id']" "$src" | \
            sed "s/id=['\"]$old_id['\"]/id=\"$new_id\"/g" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            WRITTEN_CHANNELS["$new_id"]=1
        fi
    done
done

# B. Extraction des balises <programme> (Dédoublonnage par NEW_ID + START_TIME)
xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/*.xml 2>/dev/null | \
awk -v mapping="$(for old in "${!ID_MAP[@]}"; do printf "%s=%s;" "$old" "${ID_MAP[$old]}"; done)" '
BEGIN { 
    RS="</programme>"; 
    n = split(mapping, m_array, ";");
    for (i=1; i<=n; i++) {
        split(m_array[i], pair, "=");
        if (pair[1]) dict[pair[1]] = pair[2];
    }
}
{
    if (match($0, /channel="([^"]+)"/, c) && match($0, /start="([^"]+)"/, s)) {
        old_id = c[1];
        start_key = substr(s[1], 1, 12);
        
        if (old_id in dict) {
            new_id = dict[old_id];
            line = $0;
            # Remplace l ID dans l attribut channel
            gsub("channel=\"" old_id "\"", "channel=\"" new_id "\"", line);
            
            # Dédoublonnage : Une seule diffusion par horaire par chaîne cible
            key = new_id "_" start_key;
            if (!seen[key]++) {
                sub(/^[ \t\r\n]+/, "", line);
                print line "</programme>"
            }
        }
    }
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# ==============================================================================
# NETTOYAGE ET FINITION
# ==============================================================================
rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"
echo "---"
echo "SUCCÈS : ${OUTPUT_FILE}.gz a été généré."
echo "Chaînes traitées : ${#WRITTEN_CHANNELS[@]}"
