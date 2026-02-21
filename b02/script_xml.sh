#!/bin/bash

# Configuration
CHANNEL_IDS=("TF1.fr" "France2.fr") # Ajoute tes IDs ici
URL="https://xmltvfr.fr/xmltv/xmltv.xml.gz"
OUTPUT_FILE="filtered_epg.xml"
TEMP_FILE="source.xml"

# 1. Téléchargement et décompression
echo "Téléchargement du guide TV..."
if ! curl -sL "$URL" | gunzip > "$TEMP_FILE"; then
    echo "Erreur lors du téléchargement."
    exit 1
fi

# 2. Construction de la requête de filtrage
# On crée une condition XPath : [@id='ID1' or @id='ID2']
filter_channels=""
filter_progs=""

for id in "${CHANNEL_IDS[@]}"; do
    filter_channels+="@id='$id' or "
    filter_progs+="@channel='$id' or "
done

# On retire le dernier ' or '
filter_channels="${filter_channels% or }"
filter_progs="${filter_progs% or }"

echo "Filtrage en cours..."

# 3. Utilisation de xmlstarlet de manière efficace
# On supprime tout ce qui ne correspond pas à nos IDs en une seule passe
xmlstarlet ed \
    -d "/tv/channel[not($filter_channels)]" \
    -d "/tv/programme[not($filter_progs)]" \
    "$TEMP_FILE" > "$OUTPUT_FILE"

# Nettoyage
rm "$TEMP_FILE"

echo "Terminé ! Fichier créé : $OUTPUT_FILE"
