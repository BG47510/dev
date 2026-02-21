#!/bin/bash

# ==============================================================================
# CONFIGURATION
# ==============================================================================
WORKDIR="${GITHUB_WORKSPACE:-$(pwd)}"
cd "$WORKDIR"

CHANNEL_IDS=("TF1.fr" "France2.fr" "M6.fr" "W9.fr" "Arte.tv")

URLS=(
    "https://xmltvfr.fr/xmltv/xmltv.xml.gz"
    "https://github.com/Catch-up-TV-and-More/xmltv/raw/master/tv_guide_fr.xml"
)

OUTPUT_FILE="filtered_epg.xml.gz"
TEMP_DIR="./temp_epg"
rm -rf "$TEMP_DIR" && mkdir -p "$TEMP_DIR"

# ==============================================================================
# PARAMÈTRES TEMPORELS
# ==============================================================================
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

echo "--- Démarrage du filtrage ---"

# ==============================================================================
# 1. RÉCUPÉRATION ET FILTRAGE
# ==============================================================================
idx=0
for url in "${URLS[@]}"; do
    idx=$((idx + 1))
    echo "Traitement Source $idx : $url"
    
    # On télécharge et on nettoie le DOCTYPE avant XMLStarlet
    if [[ "$url" == *.gz ]]; then
        curl -sL "$url" | gunzip > "$TEMP_DIR/raw_$idx.xml"
    else
        curl -sL "$url" > "$TEMP_DIR/raw_$idx.xml"
    fi

    # Filtrage avec xmlstarlet
    sed -i '/DOCTYPE tv SYSTEM/d' "$TEMP_DIR/raw_$idx.xml"
    
    xmlstarlet ed \
        -d "/tv/channel[not($xpath_channels)]" \
        -d "/tv/programme[not($xpath_progs)]" \
        -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
        -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
        "$TEMP_DIR/raw_$idx.xml" > "$TEMP_DIR/src_$idx.xml"
done

# ==============================================================================
# 2. FUSION, DÉDOUBLONNAGE ET COMPRESSION
# ==============================================================================
echo "Fusion et compression en cours..."

{
    echo '<?xml version="1.0" encoding="UTF-8"?><tv>'
    # Chaînes
    xmlstarlet sel -N -t -c "/tv/channel" "$TEMP_DIR"/src_*.xml | awk '!x[$0]++'
    # Programmes avec dédoublonnage (Clé : canal + début)
    xmlstarlet sel -N -t -c "/tv/programme" "$TEMP_DIR"/src_*.xml | \
    awk '
    BEGIN { RS="</programme>"; FS="<programme " }
    {
        if (match($0, /channel="([^"]+)"/, c) && match($0, /start="([^"]+)"/, s)) {
            key = c[1] s[1]
            if (!seen[key]++) { print $0 "</programme>" }
        }
    }'
    echo '</tv>'
} | gzip -9 > "$OUTPUT_FILE"

# Nettoyage
rm -rf "$TEMP_DIR"

if [ -s "$OUTPUT_FILE" ]; then
    echo "SUCCÈS : $(du -sh "$OUTPUT_FILE")"
else
    echo "ERREUR : Le fichier généré est vide."
    exit 1
fi
