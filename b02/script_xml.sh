#!/bin/bash

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# Ajoutez ou retirez des IDs de chaînes dans cette liste (séparés par des espaces)
CHANNEL_IDS=("TF1.fr" "France2.fr" "M6.fr" "W9.fr" "Arte.tv")

# URL de la source XMLTV (compressée)
URL="https://xmltvfr.fr/xmltv/xmltv.xml.gz"

# Noms des fichiers
OUTPUT_FILE="filtered_epg.xml"
TEMP_FILE="source_raw.xml"

# ==============================================================================
# TRAITEMENT
# ==============================================================================

# 1. Calcul des dates pour le filtrage (Format XMLTV : YYYYMMDDHHMMSS)
# NOW : Supprime tout ce qui est terminé avant cette seconde
# LIMIT : Supprime tout ce qui commence après 3 jours à partir de maintenant
NOW=$(date +%Y%m%d%H%M%S)
LIMIT=$(date -d "+3 days" +%Y%m%d%H%M%S)

echo "--- Démarrage du filtrage EPG ---"
echo "Fenêtre temporelle : $NOW jusqu'à $LIMIT"

# 2. Téléchargement et décompression
echo "Téléchargement du fichier source..."
if ! curl -sL "$URL" | gunzip > "$TEMP_FILE"; then
    echo "ERREUR : Impossible de télécharger ou décompresser le fichier."
    exit 1
fi

# 3. Préparation du sélecteur de chaînes pour XPath
# On transforme la liste Bash en une chaîne compatible XPath
filter_channels=""
for id in "${CHANNEL_IDS[@]}"; do
    filter_channels+="@id='$id' or "
done
filter_channels="${filter_channels% or }" # Supprime le dernier ' or '

# 4. Transformation avec XMLStarlet
# - ed : Mode édition
# - d  : Delete (suppression)
echo "Application des filtres..."

xmlstarlet ed \
    -d "/tv/channel[not($filter_channels)]" \
    -d "/tv/programme[not(contains('$(printf " %s " "${CHANNEL_IDS[@]}")', concat(' ', @channel, ' ')))]" \
    -d "/tv/programme[@stop < '$NOW']" \
    -d "/tv/programme[@start > '$LIMIT']" \
    "$TEMP_FILE" > "$OUTPUT_FILE"

# 5. Nettoyage du fichier temporaire
rm "$TEMP_FILE"

# Vérification finale
if [ -f "$OUTPUT_FILE" ]; then
    SIZE=$(du -sh "$OUTPUT_FILE" | cut -f1)
    echo "SUCCÈS : Fichier créé ($SIZE). Emplacement : $OUTPUT_FILE"
else
    echo "ERREUR : Le fichier de sortie n'a pas pu être généré."
    exit 1
fi

echo "--- Fin du traitement ---"
