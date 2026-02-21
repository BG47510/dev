#!/bin/bash

# Définir les chaînes TV qui vous intéressent
declare -a CHANNEL_IDS=("TF1.fr")  # Ajoutez d'autres IDs si nécessaire

# Liste des URLs
URLS=("https://xmltvfr.fr/xmltv/xmltv.xml.gz")

# Fichier de sortie
OUTPUT_FILE="filtered_epg.xml"
TEMP_FILE=$(mktemp)

# Créer le fichier de sortie avec l'en-tête XML
echo '<?xml version="1.0" encoding="UTF-8"?>' > "$OUTPUT_FILE"
echo '<tv>' >> "$OUTPUT_FILE"

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

    # Afficher un extrait complet du fichier pour débogage
    echo "Contenu complet du fichier source :"
    head -n 20 "$tmp_file"  # Affiche les 20 premières lignes

    # Pour chaque channel id, extraire les chaînes et programmes
    for channel_id in "${CHANNEL_IDS[@]}"; do
        echo "Extraction pour le channel_id: $channel_id"

        # Extraction des chaînes
        channel_data=$(xmlstarlet sel -t -m "/tv/channel[@id='$channel_id']" \
            -o "<channel id='$channel_id'>\n" \
            -o "<display-name>" -v "display-name" -o "</display-name>\n" \
            -o "</channel>\n" \
            "$tmp_file")

        # Extraction des programmes associés
        programmes=$(xmlstarlet sel -t -m "/tv/programme[@channel='$channel_id']" \
            -o "<programme start='{start}' stop='{stop}' channel='$channel_id'>\n" \
            -o "<title lang='fr'>" -v "title" -o "</title>\n" \
            -o "<desc lang='fr'>" -v "desc" -o "</desc>\n" \
            -o "<date>" -v "date" -o "</date>\n" \
            -o "</programme>\n" \
            "$tmp_file")

        # Ajouter la chaîne et les programmes au fichier de sortie
        if [ ! -z "$channel_data" ]; then
            echo -e "$channel_data" >> "$OUTPUT_FILE"
        fi

        if [ ! -z "$programmes" ]; then
            echo -e "$programmes" >> "$OUTPUT_FILE"
        fi
    done

    rm "$tmp_file"
}

# Parcourir toutes les URLs fournies
for url in "${URLS[@]}"; do
    extract_and_filter "$url"
done

# Fermer la balise TV
echo '</tv>' >> "$OUTPUT_FILE"

echo "Fichier EPG filtré créé: $OUTPUT_FILE"
