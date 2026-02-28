#!/bin/bash

# Aller au répertoire du script
cd "$(dirname "$0")" || exit 1

# Fichier contenant les channel_id
CHANNEL_FILE="channels.txt"
XML_FILE="programs.xml"

# Création de l'élément racine pour le XML
echo "<programs>" > "$XML_FILE"

# Lecture des channel_id depuis le fichier
while IFS= read -r line; do
    # Extraction de l'ID de la chaîne depuis la ligne
    CHANNEL_ID=$(echo "$line" | grep -oP '(?<=")[^"]+|(?<=: ")[^"]+')

    if [ -n "$CHANNEL_ID" ]; then
        DATE="$(date +%Y-%m-%d)" # Date actuelle
        URL="https://programme-tv.nouvelobs.com/chaine/$CHANNEL_ID/$DATE.php"
        
        # Récupération du contenu
        response=$(curl -s "$URL")

        # Vérification de la réponse
        if [ -z "$response" ]; then
            echo "Erreur : Aucune donnée récupérée pour $CHANNEL_ID."
            continue
        fi

        # Extraction et ajout des informations des programmes dans le fichier XML
        echo "$response" | grep -oP '(?<=<td class="logo_chaine.*?>).*?(?=</td>)' | while read -r logo; do
            echo "<program>" >> "$XML_FILE"
            echo "  <logo>$logo</logo>" >> "$XML_FILE"
        done

        echo "$response" | grep -oP '(?<=<div class="b_d prog1">).*?(?=</div>)' | while read -r desc; do
            echo "  <description>$desc</description>" >> "$XML_FILE"
        done

        echo "$response" | grep -oP '(?<=class="titre b">).*?(?=<)' | while read -r title; do
            echo "  <title>$title</title>" >> "$XML_FILE"
        done

        # Fin de l'élément program
        echo "</program>" >> "$XML_FILE"
    fi
done < "$CHANNEL_FILE"

# Fin de l'élément racine
echo "</programs>" >> "$XML_FILE"

# Formatage du XML avec xmlstarlet
xmlstarlet format "$XML_FILE" -o -v -s 4 -o > temp.xml && mv temp.xml "$XML_FILE"

echo "Fichier XML créé : $XML_FILE"
