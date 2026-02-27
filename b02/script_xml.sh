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

    # ... (téléchargement curl identique) ...
    # (votre code curl ici)

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

# ==============================================================================
# 3.B TRAITEMENT DES PROGRAMMES (DÉDOUBLONNAGE XML NATIF)
# ==============================================================================
echo "Fusion et dédoublonnage des programmes..."

# 1. On fusionne tous les programmes dans un fichier temporaire
temp_progs="$TEMP_DIR/all_progs.xml"
echo '<tv>' > "$temp_progs"
xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/*.xml >> "$temp_progs" 2>/dev/null
echo '</tv>' >> "$temp_progs"

# 2. On applique le mapping des IDs et on supprime les doublons
# On considère un doublon si : même @channel ET même @start (12 premiers chiffres)
xmlstarlet ed \
    $(for old in "${!ID_MAP[@]}"; do 
        echo "-u \"//programme[@channel='$old']/@channel\" -v \"${ID_MAP[$old]}\" "
      done) "$temp_progs" | \
xmlstarlet sel -t -m "//programme" \
    -v "." -n | \
awk -v mapping="$(for old in "${!ID_MAP[@]}"; do printf "%s=%s;" "$old" "${ID_MAP[$old]}"; done)" '
BEGIN { 
    RS="</programme>"; 
}
{
    # Extraction propre du channel et du début de date pour la clé
    if (match($0, /channel="([^"]+)"/, c) && match($0, /start="([0-9]{12})/, s)) {
        key = c[1] "_" s[1];
        if (!seen[key]++) {
            sub(/^[ \t\r\n]+/, "", $0);
            if ($0 != "") print $0 "</programme>";
        }
    }
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# Nettoyage final
rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"
echo "SUCCÈS : ${OUTPUT_FILE}.gz généré."
