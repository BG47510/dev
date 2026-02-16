#!/bin/bash

# Définir les chaînes TV qui t'intéressent
declare -a CHANNEL_IDS=("01TV.fr" "TMC+1.fr" "C4.api.telerama.fr") # Ajoute ici tous les IDs de chaînes que tu veux

# Liste des URLs (ajoute ici tes URLs)
URLS=("https://xmltvfr.fr/xmltv/xmltv.xml.gz")
#URLS=("https://xmltvfr.fr/xmltv/xmltv.xml.gz" "https://iptv-epg.org/files/epg-fr.xml.gz" "https://github.com/Catch-up-TV-and-More/xmltv/raw/master/tv_guide_fr.xml")

# Fichier de sortie
OUTPUT_FILE="filtered_epg.xml"

# Créer le fichier de sortie avec l'en-tête XML
echo '<?xml version="1.0" encoding="UTF-8"?>' > $OUTPUT_FILE
echo '<!DOCTYPE tv SYSTEM "xmltv.dtd">' >> $OUTPUT_FILE
echo '<tv>' >> $OUTPUT_FILE

# Fonction pour extraire et filtrer le contenu
extract_and_filter() {
    local url=$1
    local tmp_file=$(mktemp)

    # Télécharger et décompresser
    if [[ $url == *.gz ]]; then
        curl -s "$url" | gunzip > "$tmp_file"
    else
        curl -s "$url" > "$tmp_file"
    fi

    # Lire les lignes une par une
    while IFS= read -r line; do
        # Vérifier si la ligne contient un channel id qui nous intéresse
        for channel_id in "${CHANNEL_IDS[@]}"; do
            if echo "$line" | grep -q "channel=\"$channel_id\""; then
                echo "$line" >> $OUTPUT_FILE
                # Fox Une fois le channel trouvé, on ajoute les programmes
                while IFS= read -r programme_line; do
                    echo "$programme_line" >> $OUTPUT_FILE
                    if [[ "$programme_line" == *"</programme>"* ]]; then
                        break
                    fi
                done < <(grep -A 10 -m 1 "<programme channel=\"$channel_id\">" "$tmp_file")
            fi
        done
    done < "$tmp_file"

    rm "$tmp_file"
}

# Parcourir toutes les URL fournies
for url in "${URLS[@]}"; do
    extract_and_filter "$url"
done

echo '</tv>' >> $OUTPUT_FILE

echo "Fichier EPG filtré créé : $OUTPUT_FILE"
