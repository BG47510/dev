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

# On travaille sur un fichier XML temporaire avant de compresser
FINAL_XML="filtered_epg.xml"
OUTPUT_GZ="filtered_epg.xml.gz"
TEMP_DIR="./temp_epg"

rm -rf "$TEMP_DIR" && mkdir -p "$TEMP_DIR"
rm -f "$FINAL_XML" "$OUTPUT_GZ"

# ==============================================================================
# PARAMÈTRES TEMPORELS
# ==============================================================================
NOW=$(date -d "-6 hours" +%Y%m%d%H%M)
LIMIT=$(date -d "+3 days" +%Y%m%d%H%M)

xpath_channels=""
xpath_progs=""
for id in "${CHANNEL_IDS[@]}"; do
    xpath_channels+="@id='$id' or "
    xpath_progs+="@channel='$id' or "
done
xpath_channels="${xpath_channels% or }"
xpath_progs="${xpath_progs% or }"

# ==============================================================================
# 1. RÉCUPÉRATION ET FILTRAGE
# ==============================================================================
idx=0
for url in "${URLS[@]}"; do
    idx=$((idx + 1))
    echo ">> Source $idx : $url"
    
    # Téléchargement et décompression locale
    if [[ "$url" == *.gz ]]; then
        curl -sL "$url" | gunzip > "$TEMP_DIR/raw_$idx.xml"
    else
        curl -sL "$url" > "$TEMP_DIR/raw_$idx.xml"
    fi

    # Nettoyage DOCTYPE (indispensable pour XMLStarlet)
    sed -i '/DOCTYPE tv SYSTEM/d' "$TEMP_DIR/raw_$idx.xml"
    
    # Filtrage vers un fichier de travail
    xmlstarlet ed \
        -d "/tv/channel[not($xpath_channels)]" \
        -d "/tv/programme[not($xpath_progs)]" \
        -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
        -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
        "$TEMP_DIR/raw_$idx.xml" > "$TEMP_DIR/src_$idx.xml"
done

# ==============================================================================
# 2. FUSION ET DÉDOUBLONNAGE (VERS XML)
# ==============================================================================
echo "Fusion et dédoublonnage..."

echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$FINAL_XML"

# Ajout des chaînes uniques
xmlstarlet sel -N -t -c "/tv/channel" "$TEMP_DIR"/src_*.xml | awk '!x[$0]++' >> "$FINAL_XML"

# Ajout des programmes uniques
xmlstarlet sel -N -t -c "/tv/programme" "$TEMP_DIR"/src_*.xml | \
awk '
BEGIN { RS="</programme>"; FS="<programme " }
{
    if (match($0, /channel="([^"]+)"/, c) && match($0, /start="([^"]+)"/, s)) {
        key = c[1] s[1]
        if (!seen[key]++) { print $0 "</programme>" }
    }
}' >> "$FINAL_XML"

echo '</tv>' >> "$FINAL_XML"

# ==============================================================================
# 3. COMPRESSION ET NETTOYAGE
# ==============================================================================
if [ -s "$FINAL_XML" ]; then
    echo "Compression en cours..."
    gzip -c9 "$FINAL_XML" > "$OUTPUT_GZ"
    
    # On vérifie si le GZ a bien été créé
    if [ -f "$OUTPUT_GZ" ]; then
        echo "SUCCÈS : $(du -sh "$OUTPUT_GZ") généré."
        # Optionnel : supprimer le XML temporaire pour ne laisser que le GZ
        rm "$FINAL_XML"
    fi
else
    echo "ERREUR : Le fichier fusionné est vide."
    exit 1
fi

rm -rf "$TEMP_DIR"
