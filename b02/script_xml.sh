#!/bin/bash

# Aller au répertoire du script
cd "$(dirname "$0")" || exit 1

# ==============================================================================
# CONFIGURATION
# ==============================================================================
CHANNEL_IDS=("TF1.fr" "France2.fr" "C174.api.telerama.fr")

URLS=(
    "https://xmltvfr.fr/xmltv/xmltv.xml.gz"
    "https://github.com/Catch-up-TV-and-More/xmltv/raw/master/tv_guide_fr.xml"
)

OUTPUT_FILE="filtered_epg.xml"
TEMP_DIR="./temp_epg"
mkdir -p "$TEMP_DIR"

# ==============================================================================
# PARAMÈTRES TEMPORELS
# ==============================================================================
NOW=$(date +%Y%m%d%H%M)
LIMIT=$(date -d "+3 days" +%Y%m%d%H%M)

# Construction des filtres XPath
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
# 1. RÉCUPÉRATION ET FILTRAGE INDIVIDUEL
# ==============================================================================
count=0
for url in "${URLS[@]}"; do
    count=$((count + 1))
    echo "Source $count : $url"
    
    # Détection automatique de la compression
    if [[ "$url" == *.gz ]]; then
        FETCH_CMD="curl -sL $url | gunzip"
    else
        FETCH_CMD="curl -sL $url"
    fi

    eval "$FETCH_CMD" | xmlstarlet ed \
        -d "/tv/channel[not($xpath_channels)]" \
        -d "/tv/programme[not($xpath_progs)]" \
        -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
        -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
        > "$TEMP_DIR/src_$count.xml"
done

# ==============================================================================
# 2. FUSION ET DÉDOUBLONNAGE
# ==============================================================================
echo "Fusion et suppression des doublons..."

# Création du fichier final avec l'en-tête XMLTV
echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# A. On garde les définitions de chaînes (une seule fois par ID)
xmlstarlet sel -t -c "/tv/channel" "$TEMP_DIR"/*.xml | \
    awk '!x[$0]++' >> "$OUTPUT_FILE"

# B. On traite les programmes avec dédoublonnage intelligent
# On définit un "doublon" comme : même @channel ET même @start
xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/*.xml | \
    awk '
    BEGIN { RS="</programme>"; FS="<programme " }
    {
        if (match($0, /channel="([^"]+)"/, c) && match($0, /start="([^"]+)"/, s)) {
            key = c[1] s[1]
            if (!seen[key]++) {
                print $0 "</programme>"
            }
        }
    }' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# ==============================================================================
# NETTOYAGE
# ==============================================================================
rm -rf "$TEMP_DIR"

if [ -s "$OUTPUT_FILE" ]; then
    SIZE=$(du -sh "$OUTPUT_FILE" | cut -f1)
    echo "SUCCÈS : Fichier $OUTPUT_FILE créé ($SIZE)."
else
    echo "ERREUR : Le fichier est vide."
fi

echo "Compression du fichier final..."
gzip -f "$OUTPUT_FILE"
echo "Succès : ${OUTPUT_FILE}.gz a été généré."
