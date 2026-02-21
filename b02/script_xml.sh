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

# Créer un nouveau fichier XML
xmlstarlet ed -s / -t -n tv -v "" "$OUTPUT_FILE"

# Fonction pour extraire et filtrer le contenu
extract_and_filter() {
    local channel_id=$1

    echo "Extraction pour le channel_id: $channel_id"

    # Extraire et ajouter les chaînes
    xmlstarlet sel -t -m "/tv/channel[@id='$channel_id']" \
        -o "<channel id='$channel_id'>" \
        -o "<display-name>" -v "display-name" -o "</display-name>" \
        -o "</channel>" \
        "$TEMP_FILE" >> "$OUTPUT_FILE"

    # Extraire et ajouter les programmes associés
    xmlstarlet sel -t -m "/tv/programme[@channel='$channel_id']" \
        -o "<programme start='" -v "@start" -o "' stop='" -v "@stop" -o "' channel='$channel_id'>" \
        -o "<title lang='fr'>" -v "title" -o "</title>" \
        -o "<desc lang='fr'>" -v "desc" -o "</desc>" \
        -o "<date>" -v "date" -o "</date>" \
        -o "</programme>" \
        "$TEMP_FILE" >> "$OUTPUT_FILE"

    echo >> "$OUTPUT_FILE"  # Ajoute une ligne vide pour le formatage
}

# Parcourir toutes les chaînes définies
for channel_id in "${CHANNEL_IDS[@]}"; do
    extract_and_filter "$channel_id"
done

# Fermer la balise TV
echo '</tv>' >> "$OUTPUT_FILE"

echo "Fichier EPG filtré créé: $OUTPUT_FILE"

# Nettoyer le fichier temporaire
rm "$TEMP_FILE"
