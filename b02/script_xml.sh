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

mkdir -p "$TEMP_DIR"
# 1. CHARGEMENT DU MAPPING
declare -A ID_MAP


while IFS=',' read -r old_id new_id || [[ -n "$old_id" ]]; do
    [[ "$old_id" =~ ^\s*(#|$) ]] && continue
    old_clean=$(echo "$old_id" | tr -d '\r' | xargs)
    new_clean=$(echo "$new_id" | tr -d '\r' | xargs)
    
    if [[ -n "$old_clean" && -n "$new_clean" ]]; then
        ID_MAP["$old_clean"]="$new_clean"
        CHANNEL_IDS+=("$old_clean")
    fi
done < "$CHANNELS_FILE"

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
# 2. RÉCUPÉRATION ET FILTRAGE (AVEC PRIORITÉ)
# ==============================================================================
declare -A CHANNELS_FILLED  # Pour suivre quelle "new_id" a déjà été trouvée
count=0
mapfile -t URLS < <(grep -vE '^\s*(#|$)' "$URLS_FILE")

# Construction du filtre XPath global pour les IDs autorisés
xpath_ids=""
for id in "${!ID_MAP[@]}"; do
   xpath_ids+="@id='$id' or @channel='$id' or "
done
xpath_ids="${xpath_ids% or }"

for url in "${URLS[@]}"; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [[ -z "$url" ]] && continue

    count=$((count + 1))
    RAW_FILE="$TEMP_DIR/raw_$count.xml"
    SRC_FILE="$TEMP_DIR/src_$count.xml"

    echo "Source $count : $url"
    
    if [[ "$url" == *.gz ]]; then
        curl -sL --connect-timeout 10 "$url" | gunzip > "$RAW_FILE" 2>/dev/null
    else
        curl -sL --connect-timeout 10 "$url" > "$RAW_FILE" 2>/dev/null
    fi

    if [[ -s "$RAW_FILE" ]]; then
       # On ne garde que les programmes des chaînes qui n'ont PAS ENCORE été remplies par une source précédente



        # Pour cela, on identifie d'abord les IDs présents dans cette source


        ids_in_source=$(xmlstarlet sel -t -v "/tv/channel/@id" "$RAW_FILE" 2>/dev/null)




        # On construit un filtre spécifique pour cette source : 
        # On ne garde que si (ID est dans notre mapping) ET (le NewID n'est pas déjà pris)

        xpath_filter=""

        found_new_content=false

        for old_id in $ids_in_source; do
            new_id=${ID_MAP[$old_id]}
            if [[ -n "$new_id" ]]; then
                if [[ -z "${CHANNELS_FILLED[$new_id]}" ]]; then
                    xpath_filter+="@id='$old_id' or @channel='$old_id' or "
                    CHANNELS_FILLED["$new_id"]=1
                    found_new_content=true
                fi
            fi
        done

        xpath_filter="${xpath_filter% or }"
        if [ "$found_new_content" = true ]; then
            xmlstarlet ed \
                -d "/tv/channel[not($xpath_filter)]" \
                -d "/tv/programme[not($xpath_filter)]" \
                -d "/tv/programme[substring(@stop,1,12) < '$NOW']" \
                -d "/tv/programme[substring(@start,1,12) > '$LIMIT']" \
                "$RAW_FILE" > "$SRC_FILE" 2>/dev/null
        else
            echo "  [i] Aucun nouveau canal requis dans cette source."
            touch "$SRC_FILE" # Fichier vide pour ne pas casser la suite
        fi
        rm -f "$RAW_FILE"
    fi
done

# ==============================================================================
# 3. ASSEMBLAGE FINAL
# ==============================================================================
echo "Assemblage du fichier final..."

echo '<?xml version="1.0" encoding="UTF-8"?><tv>' > "$OUTPUT_FILE"

for src in "$TEMP_DIR"/src_*.xml; do

   [[ ! -s "$src" ]] && continue
    # Extraction et renommage des IDs à la volée
   xmlstarlet sel -t -c "/tv/channel" "$src" | \
   while read -r line; do
       for old in "${!ID_MAP[@]}"; do
           line="${line//id=\"$old\"/id=\"${ID_MAP[$old]}\"}"
       done
       echo "$line" >> "$OUTPUT_FILE"
    done
done

#  B. Programmes (Dédoublonnage interne de sécurité via AWK)
xmlstarlet sel -t -c "/tv/programme" "$TEMP_DIR"/src_*.xml 2>/dev/null | \
awk -v mapping="$(for old in "${!ID_MAP[@]}"; do printf "%s=%s;" "$old" "${ID_MAP[$old]}"; done)" '

BEGIN { RS="</programme>"; n=split(mapping,m,";"); for(i=1;i<=n;i++){split(m[i],p,"="); if(p[1]) dict[p[1]]=p[2]} }
{
       old_id=c[1]; start_k=substr(s[1],1,12);
        if (old_id in dict) {
            gsub("channel=\"" old_id "\"", "channel=\"" new_id "\"", line);
           if (!seen[new_id "_" start_k]++) {
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
