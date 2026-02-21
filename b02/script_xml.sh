#!/bin/bash

# Définir les chaînes TV qui vous intéressent
declare -a CHANNEL_IDS=("TF1.fr")  # Modifiez les IDs selon vos besoins

# Liste des URLs
URLS=("https://xmltvfr.fr/xmltv/xmltv.xml.gz")

# Fichier de sortie
OUTPUT_FILE="filtered_epg.xml"

# Initialiser le fichier de sortie
xmlstarlet ed -s / -t -n "tv" -v "" "$OUTPUT_FILE"

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
            -o "<channel id='$channel_id'>\n" \
            -o "<display-name>" -v "display-name" -o "</display-name>\n" \
            -o "</channel>" \
            "$tmp_file")

        # Ajouter les chaînes au fichier de sortie
        xmlstarlet ed -s "/tv" -i "channel" -v "$channel_data" "$OUTPUT_FILE"

        # Extraction des programmes associés
        programmes=$(xmlstarlet sel -t -m "/tv/programme[@channel='$channel_id']" \
            -o "<programme start='" -v "@start" -o "' stop='" -v "@stop" -o "' channel='$channel_id'>\n" \
            -o "<title lang='fr'>" -v "title" -o "</title>\n" \
            -o "<desc lang='fr'>" -v "desc" -o "</desc>\n" \
            -o "<date>" -v "date" -o "</date>\n" \
            -o "</programme>" \
            "$tmp_file")

        # Ajouter les programmes au fichier de sortie
        xmlstarlet ed -s "/tv" -i "programme" -v "$programmes" "$OUTPUT_FILE"
    done

    # Nettoyer le fichier temporaire
    rm "$tmp_file"
}

# Parcourir toutes les URLs fournies
for url in "${URLS[@]}"; do
    extract_and_filter "$url"
done

# Fermer la balise TV (cette étape alimentera automatiquement /tv dans xmlstarlet)
xmlstarlet ed -s "/tv" -t -n "closing-tag" -v "" "$OUTPUT_FILE"

echo "Fichier EPG filtré créé: $OUTPUT_FILE"
