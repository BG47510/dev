#!/bin/bash

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# On définit le répertoire de travail (GitHub Workspace ou dossier courant)
WORKDIR="${GITHUB_WORKSPACE:-$(pwd)}"
cd "$WORKDIR"

CHANNEL_IDS=("TF1.fr" "France2.fr" "M6.fr" "W9.fr" "Arte.tv")

URLS=(
    "https://xmltvfr.fr/xmltv/xmltv.xml.gz"
    "https://github.com/Catch-up-TV-and-More/xmltv/raw/master/tv_guide_fr.xml"
)

OUTPUT_FILE="filtered_epg.xml.gz"
TEMP_DIR="./temp_epg"
mkdir -p "$TEMP_DIR"

# ==============================================================================
# PARAMÈTRES TEMPORELS
# ==============================================================================
# Format pour XMLTV et calcul compatible Linux/Runner
NOW=$(date +%Y%m%d%H%M)
LIMIT=$(date -d "+3 days" +%Y%m%d%H%M)

xpath_channels=""
xpath_progs=""
for id in "${CHANNEL_IDS[@]}"; do
    xpath_channels+="@id='$id' or "
    xpath_progs+="@channel='$id' or "
done
xpath_channels="${xpath_channels% or }"
xpath_progs="${xpath_progs% or }"

echo "--- Démarrage du traitement dans $WORKDIR ---"

# ==============================================================================
# 1. RÉCUPÉRATION ET FILTRAGE
# ==============================================================================
count=0
for url in "${URLS[@]}"; do
    count=$((count + 1))
    echo "Source $count : $url"
    
    if [[ "$url" == *.gz ]]; then
        FETCH_CMD="curl -sL $url | gunzip"
    else
        FETCH_CMD="curl -sL $url"
    fi

    eval "$FETCH_CMD" | sed '/DOCTYPE tv SYSTEM/d' | xmlstarlet ed \
        -d "/tv/channel[not($xpath_channels)]" \
        -d "/tv/programme[not($xpath_progs)]" \
        -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
        -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
        > "$TEMP_DIR/src_$count.xml"
done

# ==============================================================================
# 2. FUSION, DÉDOUBLONNAGE ET COMPRESSION
# ==============================================================================
echo "Fusion, dédoublonnage et compression..."

{
    echo '<?xml version="1.0" encoding="UTF-8"?><tv>'
    
    # Extraction des chaînes uniques
    xmlstarlet sel -N -t -c "/tv/channel" "$TEMP_DIR"/*.xml | awk '!x[$0]++'
    
    # Extraction et dédoublonnage des programmes (clé = chaine + heure début)
    xmlstarlet sel -N -t -c "/tv/programme" "$TEMP_DIR"/*.xml | \
    awk '
    BEGIN { RS="</programme>"; FS="<programme " }
    {
        if (match($0, /channel="([^"]+)"/, c) && match($0, /start="([^"]+)"/, s)) {
            key = c[1] s[1]
            if (!seen[key]++) {
                print $0 "</programme>"
            }
        }
    }'
    
    echo '</tv>'
} | gzip -9 > "$OUTPUT_FILE"

# ==============================================================================
# NETTOYAGE
# ==============================================================================
rm -rf "$TEMP_DIR"

if [ -s "$OUTPUT_FILE" ]; then
    echo "SUCCÈS : $(du -sh "$OUTPUT_FILE") généré dans $WORKDIR"
else
    echo "ERREUR : Échec de la génération."
    exit 1
fi
