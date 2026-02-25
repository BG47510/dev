#!/bin/bash

# Aller au répertoire du script
cd "$(dirname "$0")" || exit 1

# ==============================================================================
# CONFIGURATION
# ==============================================================================
CHANNELS_FILE="channels.txt"  # Votre nouveau fichier : ancien_id,nouvel_id
URLS_FILE="urls.txt"
OUTPUT_FILE="filtered_epg.xml"
TEMP_DIR="./temp_epg"

# Vérification des fichiers de configuration
for f in "$CHANNELS_FILE" "$URLS_FILE"; do
    if [[ ! -f "$f" ]]; then
        echo "Erreur : Le fichier $f est introuvable."
        exit 1
    fi
done

# 1. CHARGEMENT DU MAPPING (Tableau associatif Bash)
# On crée un dictionnaire : ID_MAP[ancien_id] = nouvel_id
declare -A ID_MAP
CHANNEL_IDS=()

while IFS=',' read -r old_id new_id || [[ -n "$old_id" ]]; do
    # Ignore les commentaires (#) et les lignes vides
    [[ "$old_id" =~ ^\s*(#|$) ]] && continue
    
    # Nettoyage des espaces et caractères invisibles (\r)
    old_clean=$(echo "$old_id" | tr -d '\r' | xargs)
    new_clean=$(echo "$new_id" | tr -d '\r' | xargs)
    
    if [[ -n "$old_clean" && -n "$new_clean" ]]; then
        ID_MAP["$old_clean"]="$new_clean"
        CHANNEL_IDS+=("$old_clean")
    fi
done < "$CHANNELS_FILE"

mkdir -p "$TEMP_DIR"

# ==============================================================================
# PARAMÈTRES TEMPORELS
# ==============================================================================
NOW=$(date +%Y%m%d%H%M)
LIMIT=$(date -d "+3 days" +%Y%m%d%H%M)

# Construction des filtres XPath pour les IDs d'origine
xpath_channels=""
xpath_progs=""
for id in "${CHANNEL_IDS[@]}"; do
    xpath_channels+="@id='$id' or "
    xpath_progs+="@channel='$id' or "
done
xpath_channels="${xpath_channels% or }"
xpath_progs="${xpath_progs% or }"

echo "--- Démarrage du traitement ---"

# ==============================================================================
# 2. RÉCUPÉRATION ET FILTRAGE XMLSTARLET
# ==============================================================================
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

count=0
for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [[ -z "$url" ]] && continue

    count=$((count + 1))
    echo "Source $count : $url"
    RAW_FILE="$TEMP_DIR/raw_$count.xml"
    
    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 10 --max-time 30 --fail "$url" | gunzip > "$RAW_FILE" 2>/dev/null
    else
        curl -sL --connect-timeout 10 --max-time 30 --fail "$url" > "$RAW_FILE" 2>/dev/null
    fi

    if [[ -s "$RAW_FILE" ]]; then
        # Filtrage initial (on ne garde que les IDs présents dans choix.txt)
        if ! xmlstarlet ed \
            -d "/tv/channel[not($xpath_channels)]" \
            -d "/tv/programme[not($xpath_progs)]" \
            -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
            -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
            "$RAW_FILE" > "$TEMP_DIR/src_$count.xml" 2>/dev/null; then
            echo "Attention : Erreur XML source $count"
        fi
        rm -f "$RAW_FILE"
    else
        echo "Attention : Source $count vide ou erreur de téléchargement"
    fi
done

# ==============================================================================
# 3. FUSION, RENOMMAGE (MAPPING) ET DÉDOUBLONNAGE
# ==============================================================================
echo "Fusion, renommage des IDs et suppression des doublons..."

# Préparation de la chaîne de mapping pour AWK (format: old1=new1;old2=new2)
map_str=""
for old in "${!ID_MAP[@]}"; do
    map_str+="$old=${ID_MAP[$old]};"
done

# Création du fichier final
echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# A. Traitement des balises <channel> avec remplacement d'ID
# On utilise sed pour remplacer id="ancien" par id="nouveau"
for old_id in "${!ID_MAP[@]}"; do
    new_id=${ID_MAP[$old_id]}
    xmlstarlet sel -t -c "/tv/channel[@id='$old_id']" "$TEMP_DIR"/*.xml 2>/dev/null | \
    sed "s/id=\"$old_id\"/id=\"$new_id\"/g" | \
    awk '!x[$0]++' >> "$OUTPUT_FILE"
done

# B. Traitement des balises <programme> avec mapping dynamique AWK
xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/*.xml 2>/dev/null | \
awk -v mapping="$map_str" '
BEGIN { 
    RS="</programme>"; 
    # Charger le mapping dans un tableau AWK interne
    n = split(mapping, a, ";");
    for (i=1; i<=n; i++) {
        split(a[i], pair, "=");
        if (pair[1]) dict[pair[1]] = pair[2];
    }
}
{
    # Extraire l ancien ID de la chaîne et la date de début
    if (match($0, /channel="([^"]+)"/, c) && match($0, /start="([^"]+)"/, s)) {
        old_id = c[1];
        start_val = s[1];
        
        # Si l ID existe dans notre dictionnaire, on le remplace
        if (old_id in dict) {
            new_id = dict[old_id];
            # Remplacement textuel de l attribut channel
            gsub("channel=\"" old_id "\"", "channel=\"" new_id "\"", $0);
            
            # Dédoublonnage sur la base du NOUVEL ID + DATE DE DÉBUT
            key = new_id start_val;
            if (!seen[key]++) {
                print $0 "</programme>"
            }
        }
    }
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# ==============================================================================
# NETTOYAGE ET FINALISATION
# ==============================================================================
rm -rf "$TEMP_DIR"

if [ -s "$OUTPUT_FILE" ]; then
    echo "Compression du fichier final..."
    gzip -f "$OUTPUT_FILE"
    echo "SUCCÈS : ${OUTPUT_FILE}.gz a été généré."
else
    echo "ERREUR : Le fichier final est vide."
fi
