#!/bin/bash

# Définir les chaînes TV qui t'intéressent
declare -a CHANNEL_IDS=("01TV.fr") # Remplace par les IDs de chaînes souhaitées

# Liste des URLs
URLS=("https://xmltvfr.fr/xmltv/xmltv.xml.gz")

# Fichier de sortie
OUTPUT_FILE="filtered_epg.xml"

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

    # Afficher une partie du fichier pour le débogage
    echo "Contenu du fichier source :"
    head -n 20 "$tmp_file"  # Affiche les 20 premières lignes

    # Pour chaque channel id, extraire les chaînes et programmes
    for channel_id in "${CHANNEL_IDS[@]}"; do
        echo "Extraction pour le channel_id : $channel_id"
      
        local extracted=$(xmlstarlet sel -t -m "/tv/channel[@id='$channel_id'] | /tv/programme[@channel='$channel_id']" -o "\n" "$tmp_file")
        
        if [ -z "$extracted" ]; then
            echo "Aucune donnée trouvée pour $channel_id dans le fichier."
        else
            echo "$extracted" >> "$OUTPUT_FILE"
        fi
    done

    rm "$tmp_file"
}

# Parcourir toutes les URLs fournies
for url in "${URLS[@]}"; do
    extract_and_filter "$url"
done

echo '</tv>' >> "$OUTPUT_FILE"
echo "Fichier EPG filtré créé : $OUTPUT_FILE"
