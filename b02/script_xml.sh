#!/bin/bash

# Définir les chaînes TV qui vous intéressent
declare -a CHANNEL_IDS=("TF1.fr")  # Modifiez les IDs selon vos besoins

# Liste des URLs
URLS=("https://xmltvfr.fr/xmltv/xmltv.xml.gz")

# Fichier de sortie
OUTPUT_FILE="filtered_epg.xml"
TEMP_FILE=$(mktemp)

# Télécharger et décompresser
if ! curl -s "${URLS[0]}" | gunzip > "$TEMP_FILE"; then
    echo "Erreur lors du téléchargement de ${URLS[0]}"
    exit 1
fi

# Retirer la ligne DTD si elle existe
sed -i 's|<!DOCTYPE tv SYSTEM "xmltv.dtd">||' "$TEMP_FILE"

# Créer le fichier de sortie avec l'en-tête XML
{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<tv>'
} > "$OUTPUT_FILE"

# Fonction pour extraire et filtrer le contenu
extract_and_filter() {
    local channel_id=$1

    echo "Extraction pour le channel_id: $channel_id"

    # Extraction des chaînes
    channel_data=$(xmlstarlet sel -t -m "/tv/channel[@id='$channel_id']" \
        -o "<channel id='$channel_id'>\n" \
        -o "<display-name>" -v "display-name" -o "</display-name>\n" \
        -o "</channel>" \
        "$TEMP_FILE")

    # Écrire les chaînes dans le fichier de sortie
    echo -e "$channel_data" >> "$OUTPUT_FILE"

    # Extraction des programmes associés
    programmes=$(xmlstarlet sel -t -m "/tv/programme[@channel='$channel_id']" \
        -o "<programme start='" -v "@start" -o "' stop='" -v "@stop" -o "' channel='$channel_id'>\n" \
        -o "<title lang='fr'>" -v "title" -o "</title>\n" \
        -o "<desc lang='fr'>" -v "desc" -o "</desc>\n" \
        -o "<date>" -v "date" -o "</date>\n" \
        -o "</programme>" \
        "$TEMP_FILE")

    # Écrire les programmes dans le fichier de sortie
    echo -e "$programmes" >> "$OUTPUT_FILE"
}

# Parcourir toutes les chaînes définies
for channel_id in "${CHANNEL_IDS[@]}"; do
    extract_and_filter "$channel_id"
done

# Fermer la balise TV
echo '</tv>' >> "$OUTPUT_FILE"

# Nettoyer le fichier temporaire
rm "$TEMP_FILE"

echo "Fichier EPG filtré créé: $OUTPUT_FILE"
