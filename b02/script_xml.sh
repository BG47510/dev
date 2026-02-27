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
# 2. RÉCUPÉRATION ET FILTRAGE XMLSTARLET
# ==============================================================================
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

count=0
for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [[ -z "$url" ]] && continue

    count=$((count + 1))
    echo "Source $count : $url"
    RAW_FILE="$TEMP_DIR/raw_$count.xml"
    
    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 10 --max-time 30 --fail "$url" | gunzip > "$RAW_FILE" 2>/dev/null
    else
        curl -sL --connect-timeout 10 --max-time 30 --fail "$url" > "$RAW_FILE" 2>/dev/null
    fi

    if [[ -s "$RAW_FILE" ]]; then
        # On ne garde que les IDs présents dans channels.txt
        if ! xmlstarlet ed \
            -d "/tv/channel[not($xpath_channels)]" \
            -d "/tv/programme[not($xpath_progs)]" \
            -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
            -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
            "$RAW_FILE" > "$TEMP_DIR/src_$count.xml" 2>/dev/null; then
            echo "Attention : Erreur XML source $count"
        fi
        rm -f "$RAW_FILE"
    else
        echo "Attention : Source $count vide ou erreur"
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
# 3.B TRAITEMENT DES PROGRAMMES (DÉDOUBLONNAGE ROBUSTE)
# ==============================================================================
echo "Traitement des programmes..."

# On extrait tous les programmes et on les traite avec un AWK amélioré
xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/*.xml 2>/dev/null | \
awk -v mapping="$(for old in "${!ID_MAP[@]}"; do printf "%s=%s;" "$old" "${ID_MAP[$old]}"; done)" '
BEGIN { 
    RS="</programme>"; 
    FS=">";
    n = split(mapping, m_list, ";");
    for (i=1; i<=n; i++) {
        split(m_list[i], pair, "=");
        if (pair[1]) dict[pair[1]] = pair[2];
    }
}
{
    # 1. Extraire les valeurs proprement via regex, peu importe l ordre
    # On cherche channel="...", start="..."
    if (match($0, /channel="([^"]+)"/, c) && match($0, /start="([0-9]{12})/, s)) {
        old_id = c[1];
        start_key = s[1]; # On ne prend que les 12 premiers chiffres (AAAAMMDDHHMM)

        if (old_id in dict) {
            new_id = dict[old_id];
            
            # 2. Créer une clé unique : NEWID + DATE_COURTE
            key = new_id "_" start_key;
            
            if (!seen[key]++) {
                line = $0;
                # Remplacer le channel ID dans la ligne
                gsub("channel=\"" old_id "\"", "channel=\"" new_id "\"", line);
                
                # Nettoyer les espaces/retours chariot en début de bloc
                sub(/^[ \t\r\n]+/, "", line);
                
                if (line != "") {
                    print line "</programme>";
                }
            }
        }
    }
}' >> "$OUTPUT_FILE"

echo '</tv>' >> "$OUTPUT_FILE"

# Nettoyage final
rm -rf "$TEMP_DIR"
gzip -f "$OUTPUT_FILE"
echo "SUCCÈS : ${OUTPUT_FILE}.gz généré."
