#!/bin/bash

# Définir les chaînes TV qui vous intéressent
declare -a CHANNEL_IDS=("TF1.fr" "02TV.fr")  # Remplacez par les IDs de chaînes souhaitées

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
    curl -s "$url" | gunzip > "$tmp_file"

    # Retirer la ligne DTD si elle existe
    sed -i 's|<!DOCTYPE tv SYSTEM "xmltv.dtd">||' "$tmp_file"

    # Cran d'affichage pour le débogage
    echo "Contenu du fichier source :"
    head -n 20 "$tmp_file"  # Afficher 20 premières lignes

    # Pour chaque channel id, extraire les chaînes et programmes
    for channel_id in "${CHANNEL_IDS[@]}"; do
        echo "Extraction pour le channel_id: $channel_id"
      
        xmlstarlet sel -t -m "/tv/channel[@id='$channel_id'] | /tv/programme[@channel='$channel_id']" "$tmp_file" >> "$TEMP_FILE"
    done

    rm "$tmp_file"
}

# Parcourir toutes les URLs fournies
for url in "${URLS[@]}"; do
    extract_and_filter "$url"
done

# Filtrer les doublons et lignes vides
sort -u "$TEMP_FILE" | grep -v '^$' >> "$OUTPUT_FILE"

# Ajouter la fermeture de la balise tv
echo '</tv>' >> "$OUTPUT_FILE"

# Nettoyer le fichier temporaire
rm "$TEMP_FILE"

echo "Fichier EPG filtré créé: $OUTPUT_FILE"
