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
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

# Tableau pour suivre les NEW_ID (destinations) déjà complétés
declare -A COMPLETED_DESTINATIONS

count=0
for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [[ -z "$url" ]] && continue

    # On prépare le filtre XPath uniquement pour les IDs non encore trouvés
    xpath_channels=""
    xpath_progs=""
    needed_in_this_source=0

    for old_id in "${!ID_MAP[@]}"; do
        dest_id=${ID_MAP[$old_id]}
        # Si on n'a pas encore de données pour cet ID de destination final
        if [[ -z "${COMPLETED_DESTINATIONS[$dest_id]}" ]]; then
            xpath_channels+="@id='$old_id' or "
            xpath_progs+="@channel='$old_id' or "
            ((needed_in_this_source++))
        fi
    done

    # Si toutes les chaînes ont été trouvées dans les URLs précédentes, on stoppe
    if [[ $needed_in_this_source -eq 0 ]]; then
        echo "Toutes les chaînes ont été récupérées. Fin anticipée."
        break
    fi

    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 10 --max-time 30 --fail "$url" | gunzip > "$RAW_FILE" 2>/dev/null
    else
        curl -sL --connect-timeout 10 --max-time 30 --fail "$url" > "$RAW_FILE" 2>/dev/null
    fi

    if [[ -s "$RAW_FILE" ]]; then
        xpath_channels="${xpath_channels% or }"
        xpath_progs="${xpath_progs% or }"

        # Filtrage immédiat pour ne garder que ce qui est utile (non encore trouvé)
        if xmlstarlet ed \
            -d "/tv/channel[not($xpath_channels)]" \
            -d "/tv/programme[not($xpath_progs)]" \
            -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
            -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
            "$RAW_FILE" > "$TEMP_DIR/src_$count.xml" 2>/dev/null; then
            
            # On identifie les OLD_IDs trouvés dans ce fichier
            found_old_ids=$(xmlstarlet sel -t -v "/tv/channel/@id" "$TEMP_DIR/src_$count.xml" 2>/dev/null)
            
            for f_old in $found_old_ids; do
                # On marque le NEW_ID correspondant comme complété
                dest_found=${ID_MAP[$f_old]}
                if [[ -n "$dest_found" ]]; then
                    COMPLETED_DESTINATIONS["$dest_found"]=1
                fi
            done
        fi
        rm -f "$RAW_FILE"
    fi
done
    

# ==============================================================================
# 3. FUSION, RENOMMAGE PRÉCIS ET DÉDOUBLONNAGE
# ==============================================================================
echo "Fusion et traitement final..."

echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

# ==============================================================================
# 3.A TRAITEMENT DES BALISES <CHANNEL> (VERSION FIABLE)
# ==============================================================================
echo "Extraction des chaînes uniques..."

# Tableau pour suivre les IDs déjà écrits dans le fichier final
declare -A SEEN_CHANNELS

for old_id in "${!ID_MAP[@]}"; do
    new_id=${ID_MAP[$old_id]}
    
    # On saute si on a déjà ajouté cette chaîne (évite les doublons d'ID)
    [[ -n "${SEEN_CHANNELS[$new_id]}" ]] && continue

    # 1. On extrait le bloc complet <channel>...</channel> depuis les fichiers temporaires
    # 2. On change l'attribut 'id' pour mettre le 'new_id'
    channel_block=$(xmlstarlet sel -t -c "/tv/channel[@id='$old_id'][1]" "$TEMP_DIR"/*.xml 2>/dev/null | \
                    xmlstarlet ed -u "/channel/@id" -v "$new_id" 2>/dev/null)

    if [[ -n "$channel_block" ]]; then
        # On s'assure qu'il y a un saut de ligne après la balise pour la lisibilité
        echo "$channel_block" >> "$OUTPUT_FILE"
        SEEN_CHANNELS["$new_id"]=1
    fi
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
