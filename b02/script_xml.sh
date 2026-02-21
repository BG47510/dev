#!/bin/bash

# Définir les chaînes TV qui vous intéressent
declare -a CHANNEL_IDS=("TF1.fr")  # Modifiez les IDs selon vos besoins

# Liste des URLs
URLS=("https://xmltvfr.fr/xmltv/xmltv.xml.gz")

# Fichier de sortie
OUTPUT_FILE="filtered_epg.xml"

# Créer le fichier de sortie avec l'en-tête XML
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<tv>'
} > "$OUTPUT_FILE"

# Fonction pour extraire et filtrer le contenu
extract_and_filter() {
    local url=$1
    local tmp_file=$(mktemp)

    # Télécharger et décompresser
    if ! curl -s "$url" | gunzip > "$tmp_file"; then
        echo "Erreur lors du téléchargement de $url"
        return
    fi

    # Retirer la ligne DTD si elle existe
    sed -i 's|<!DOCTYPE tv SYSTEM "xmltv.dtd">||' "$tmp_file"

    # Pour chaque channel id, extraire les chaînes et programmes
    for channel_id in "${CHANNEL_IDS[@]}"; do
        echo "Extraction pour le channel_id: $channel_id"

        # Extraction des chaînes
        channel_data=$(xmlstarlet sel -t -m "/tv/channel[@id='$channel_id']" \
            -o "<channel id='$channel_id'>" \
            -o "<display-name>" -v "display-name" -o "</display-name>" \
            -o "</channel>" \
            "$tmp_file")

        # Écrire les chaînes dans le fichier de sortie
        echo "$channel_data" >> "$OUTPUT_FILE"

        # Extraction des programmes associés
        programmes=$(xmlstarlet sel -t -m "/tv/programme[@channel='$channel_id']" \
            -o "<programme start='" -v "@start" -o "' stop='" -v "@stop" -o "' channel='$channel_id'>" \
            -o "<title lang='fr'>" -v "title" -o "</title>" \
            -o "<desc lang='fr'>" -v "desc" -o "</desc>" \
            -o "<date>" -v "date" -o "</date>" \
            -o "</programme>" \
            "$tmp_file")

        # Écrire les programmes dans le fichier de sortie
        echo "$programmes" >> "$OUTPUT_FILE"
    done

    # Nettoyer le fichier temporaire
    rm "$tmp_file"
}

# Parcourir toutes les URLs fournies
for url in "${URLS[@]}"; do
    extract_and_filter "$url"
done

# Fermer la balise TV
echo '</tv>' >> "$OUTPUT_FILE"

echo "Fichier EPG filtré créé: $OUTPUT_FILE"
