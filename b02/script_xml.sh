#!/bin/bash

# Aller au répertoire du script
cd "$(dirname "$0")" || exit 1

# ==============================================================================
# CONFIGURATION
# ==============================================================================
CHANNELS_FILE="channels.txt"
URLS_FILE="urls.txt"
OUTPUT_FILE="epg.xml"
TEMP_DIR="./temp_epg"

# Vérification des fichiers
for f in "$CHANNELS_FILE" "$URLS_FILE"; do
    if [[ ! -f "$f" ]]; then
        echo "Erreur : Le fichier $f est introuvable."
        exit 1
    fi
done

# 1. CHARGEMENT DU MAPPING
declare -A ID_MAP
CHANNEL_IDS=()

while IFS=',' read -r old_id new_id || [[ -n "$old_id" ]]; do
    [[ "$old_id" =~ ^\s*(#|$) ]] && continue
    old_clean=$(echo "$old_id" | tr -d '\r' | xargs)
    new_clean=$(echo "$new_id" | tr -d '\r' | xargs)
    
    if [[ -n "$old_clean" && -n "$new_clean" ]]; then
        ID_MAP["$old_clean"]="$new_clean"
        CHANNEL_IDS+=("$old_clean")
    fi
done < "$CHANNELS_FILE"

mkdir -p "$TEMP_DIR"

# PARAMÈTRES TEMPORELS
NOW=$(date +%Y%m%d%H%M)
LIMIT=$(date -d "+1 days" +%Y%m%d%H%M)

# Construction des filtres XPath
xpath_channels=""
xpath_progs=""
for id in "${CHANNEL_IDS[@]}"; do
    xpath_channels+="@id='$id' or "
    xpath_progs+="@channel='$id' or "
done
xpath_channels="${xpath_channels% or }"
xpath_progs="${xpath_progs% or }"

echo "--- Démarrage du traitement ---"

# ==============================================================================
# 2. RÉCUPÉRATION ET FILTRAGE INTELLIGENT
# ==============================================================================
declare -A COMPLETED_DESTINATIONS
count=0

echo "--- Début de la récupération des sources ---"

mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [[ -z "$url" ]] && continue

    # 1. Construire le filtre pour les IDs encore manquants
    xpath_channels=""
    xpath_progs=""
    needed_count=0

    for old_id in "${!ID_MAP[@]}"; do
        dest_id=${ID_MAP[$old_id]}
        if [[ -z "${COMPLETED_DESTINATIONS[$dest_id]}" ]]; then
            xpath_channels+="@id='$old_id' or "
            xpath_progs+="@channel='$old_id' or "
            ((needed_count++))
        fi
    done

    if [[ $needed_count -eq 0 ]]; then
        echo "Info : Toutes les chaînes cibles ont été complétées."
        break
    fi

    xpath_channels="${xpath_channels% or }"
    xpath_progs="${xpath_progs% or }"

    count=$((count + 1))
    RAW_FILE="$TEMP_DIR/raw_$count.xml"
    SRC_FILE="$TEMP_DIR/src_$count.xml"

    echo "Source $count : $url ($needed_count chaînes attendues)"
    
    # Téléchargement
    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 10 --fail "$url" | gunzip > "$RAW_FILE" 2>/dev/null
    else
        curl -sL --connect-timeout 10 --fail "$url" > "$RAW_FILE" 2>/dev/null
    fi

    if [[ -s "$RAW_FILE" ]]; then
        # Filtrage : On ne garde que les programmes des IDs manquants
        xmlstarlet ed \
            -d "/tv/channel[not($xpath_channels)]" \
            -d "/tv/programme[not($xpath_progs)]" \
            -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
            -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
            "$RAW_FILE" > "$SRC_FILE" 2>/dev/null

        # On vérifie ce qu'on a réellement récupéré dans ce fichier
        found_here=$(xmlstarlet sel -t -v "/tv/channel/@id" "$SRC_FILE" 2>/dev/null)
        
        for f_old in $found_here; do
            dest_found=${ID_MAP[$f_old]}
            if [[ -n "$dest_found" && -z "${COMPLETED_DESTINATIONS[$dest_found]}" ]]; then
                echo "  [+] Trouvé : $f_old -> $dest_found"
                COMPLETED_DESTINATIONS["$dest_found"]=1
            fi
        done
        rm -f "$RAW_FILE"
    else
        echo "  [!] Erreur de téléchargement ou fichier vide."
    fi
done

# ==============================================================================
# 3. ASSEMBLAGE FINAL
# ==============================================================================
echo "Assemblage du fichier final..."
echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# A. Canaux (On prend le premier bloc trouvé pour chaque destination)
declare -A WRITTEN_CHANNELS
for src in "$TEMP_DIR"/src_*.xml; do
    [[ ! -f "$src" ]] && continue
    
    # On extrait chaque channel du fichier source
    while read -r old_id; do
        new_id=${ID_MAP[$old_id]}
        if [[ -n "$new_id" && -z "${WRITTEN_CHANNELS[$new_id]}" ]]; then
            # Extraction et renommage de l'ID en une seule passe
            xmlstarlet sel -t -c "/tv/channel[@id='$old_id']" "$src" | \
            xmlstarlet ed -u "/channel/@id" -v "$new_id" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            WRITTEN_CHANNELS["$new_id"]=1
        fi
    done < <(xmlstarlet sel -t -v "/tv/channel/@id" "$src")
done


# B. Traitement des balises <programme> avec mapping et dédoublonnage robuste
# Correction : La regex match() est insensible à l'ordre des attributs
xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/*.xml 2>/dev/null | \
awk -v mapping="$(for old in "${!ID_MAP[@]}"; do printf "%s=%s;" "$old" "${ID_MAP[$old]}"; done)" '
BEGIN { 
    RS="</programme>"; 
    n = split(mapping, a, ";");
    for (i=1; i<=n; i++) {
        split(a[i], pair, "=");
        if (pair[1]) dict[pair[1]] = pair[2];
    }
}
{
    # On cherche channel="..." et start="..." peu importe où ils sont dans la ligne
    if (match($0, /channel="([^"]+)"/, c) && match($0, /start="([^"]+)"/, s)) {
        old_id = c[1];
        start_full = s[1];
        # On ne garde que les 12 premiers chiffres pour ignorer les fuseaux horaires (+0100)
        start_key = substr(start_full, 1, 12);
        
        if (old_id in dict) {
            new_id = dict[old_id];
            
            # Remplacement ciblé de l attribut channel uniquement
            # Le reste du contenu (display-name, title) est préservé
            line = $0;
            gsub("channel=\"" old_id "\"", "channel=\"" new_id "\"", line);
            
            # Dédoublonnage sur NOUVEL_ID + DATE_COURTE
            key = new_id "_" start_key;
            if (!seen[key]++) {
                # Nettoyage des sauts de ligne inutiles et fermeture
                sub(/^[ \t\r\n]+/, "", line);
                print line "</programme>"
            }
        }
    }
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# Nettoyage final
rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"
echo "SUCCÈS : ${OUTPUT_FILE}.gz généré."
