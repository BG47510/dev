#!/bin/bash

# Aller au répertoire du script
cd "$(dirname "$0")" || exit 1

# --- CONFIGURATION ---
CHANNELS_FILE="channels.txt"
URLS_FILE="urls.txt"
OUTPUT_FILE="epg.xml"
TEMP_DIR="./temp_epg"

mkdir -p "$TEMP_DIR"
rm -f "$TEMP_DIR"/* # Nettoyage au démarrage

# 1. CHARGEMENT DU MAPPING
declare -A ID_MAP
while IFS=',' read -r old_id new_id || [[ -n "$old_id" ]]; do
    [[ "$old_id" =~ ^\s*(#|$) ]] && continue
    old_clean=$(echo "$old_id" | tr -d '\r' | xargs)
    new_clean=$(echo "$new_id" | tr -d '\r' | xargs)
    [[ -n "$old_clean" && -n "$new_clean" ]] && ID_MAP["$old_clean"]="$new_clean"
done < "$CHANNELS_FILE"

# 2. TRAITEMENT DES SOURCES
echo "--- Récupération des données ---"
count=0
while read -r url || [[ -n "$url" ]]; do
    [[ "$url" =~ ^\s*(#|$) || -z "$url" ]] && continue
    count=$((count + 1))
    echo "Source $count : $url"
    
    RAW="$TEMP_DIR/raw_$count.xml"
    
    # Timeout strict de 15s pour éviter que curl ne bloque le script
    if [[ "$url" == *.gz ]]; then
        curl -sL --max-time 15 --connect-timeout 10 "$url" | gunzip > "$RAW" 2>/dev/null
    else
        curl -sL --max-time 15 --connect-timeout 10 "$url" > "$RAW" 2>/dev/null
    fi

    if [[ -s "$RAW" ]]; then
        # Extraction normalisée vers un fichier plat (ID | START | XML_BLOC)
        # On utilise une balise personnalisée [SEP] pour éviter les conflits
        xmlstarlet sel -t -m "/tv/programme" \
            -v "@channel" -o " " -v "substring(@start,1,12)" -o " " -c "." -n \
            "$RAW" 2>/dev/null >> "$TEMP_DIR/all_progs.txt"
    fi
    rm -f "$RAW"
done < "$URLS_FILE"

# 3. ASSEMBLAGE FINAL
echo "--- Création du XML final ---"
echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# A. Génération propre des canaux
for old in "${!ID_MAP[@]}"; do
    new="${ID_MAP[$old]}"
    if [[ -z "${DONE_CHANNELS[$new]}" ]]; then
        echo "  <channel id=\"$new\"><display-name>$new</display-name></channel>" >> "$OUTPUT_FILE"
        DONE_CHANNELS["$new"]=1
    fi
done

# B. Fusion et Dédoublonnage des programmes (Bash + Sed pour la vitesse)
# On trie le fichier de travail pour que awk traite les données dans l'ordre
sort -k1,1 -k2,2 "$TEMP_DIR/all_progs.txt" | awk -v mapping="$(for old in "${!ID_MAP[@]}"; do printf "%s=%s;" "$old" "${ID_MAP[$old]}"; done)" '
BEGIN {
    split(mapping, m_array, ";");
    for (i in m_array) {
        split(m_array[i], pair, "=");
        if (pair[1]) dict[pair[1]] = pair[2];
    }
}
{
    old_id = $1;
    start_key = $2;
    # Le reste de la ligne est le bloc XML
    xml_content = substr($0, length(old_id) + length(start_key) + 3);

    if (old_id in dict) {
        new_id = dict[old_id];
        key = new_id "_" start_key;
        
        if (!seen[key]++) {
            # Remplacement propre de l ID
            gsub("channel=\"" old_id "\"", "channel=\"" new_id "\"", xml_content);
            print xml_content;
        }
    }
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# 4. FINALISATION
# On s'assure que les balises orphelines (problème précédent) sont corrigées
sed -i 's/><programme/ /g' "$OUTPUT_FILE" # Nettoyage si xmlstarlet a collé des balises

rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"
echo "Succès : ${OUTPUT_FILE}.gz"
