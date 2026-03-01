#!/bin/bash

# Aller au répertoire du script
cd "$(dirname "$0")" || exit 1

# Définir les paramètres
REGION="fr"
ENABLE_DETAILS=true
API_KEY=""
DATE="2023-10-01"              # Utilisez la date souhaitée
OUTPUT_XML="epg.xml"           # Nom du fichier de sortie XML
CHANNELS_FILE="channels.txt"   # Fichier contenant les ID des chaînes

# Définir les en-têtes pour les requêtes HTTP
HEADERS=(
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
  -H "Accept-Language: fr-FR,fr-CA;q=0.9,en;q=0.8,en-US;q=0.7"
  -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:95.0) Gecko/20100101 Firefox/95.0"
)

# Fonction pour obtenir la clé API
get_api_key() {
  if [[ -z "$API_KEY" ]]; then
    result=$(curl -s "https://www.canalplus.com/$REGION/programme-tv/" "${HEADERS[@]}")
    API_KEY=$(echo "$result" | grep -oP '"token":"\K[^"]+')
    
    if [[ -z "$API_KEY" ]]; then
      echo "Impossible de récupérer la clé API MyCanal"
      exit 1
    fi
  fi
  echo "$API_KEY"
}

# Fonction pour obtenir la liste des programmes
get_program_list() {
  local channel_id="$1"
  local date="$2"
  local program_list=()
  local min_start=$(date -d "$date -1 day" +%s)
  local max_start=$(date -d "$date +1 day" +%s)
  local start_date="$(date -d "$date -1 day" +%Y-%m-%d)"

  while true; do
    url="https://hodor.canalplus.pro/api/v2/mycanal/channels/$(get_api_key)/$channel_id/broadcasts/day/$(($(date -d "$start_date" +%s) / 86400 - $(date -d '1970-01-01' +%s) / 86400))"
    
    json=$(curl -s "$url" "${HEADERS[@]}")
    time_slices=$(echo "$json" | jq -r '.timeSlices')

    if [[ "$time_slices" == "null" ]]; then
      break
    fi

    # Traiter chaque programme
    echo "$time_slices" | jq -c '.[] | .contents[]' | while IFS= read -r program; do
      start_time=$(echo "$program" | jq -r '.startTime')
      title=$(echo "$program" | jq -r '.title')
      subtitle=$(echo "$program" | jq -r '.subtitle // empty')
      URLPage=$(echo "$program" | jq -r '.onClick.URLPage')

      if (( start_time < min_start )) || (( start_time > max_start )); then
        continue
      fi

      program_list+=("$start_time|$title|$subtitle|$URLPage") # Stocker au format "startTime|title|subtitle|URLPage"
    done

    start_date="$(date -d "$start_date +1 day" +%Y-%m-%d)"
  done

  echo "${program_list[@]}"
}

# Fonction pour récupérer les détails
fetch_details() {
  local program_list=("$@")

  for program in "${program_list[@]}"; do
    IFS='|' read -r start_time title subtitle URLPage <<< "$program"
    detail=$(curl -s "$URLPage" "${HEADERS[@]}")

    # Extrait les détails nécessaires
    program_details=$(echo "$detail" | jq -r '{
      title: .detail.informations.title // "'"$title"'",
      subtitle: .episodes.contents[0].subtitle // "'"$subtitle"'",
      description: .episodes.contents[0].summary // .detail.informations.summary,
      season: .detail.selectedEpisode.seasonNumber,
      episode: .detail.selectedEpisode.episodeNumber,
      genre: .tracking.dataLayer.genre,
      genreDetailed: .tracking.dataLayer.subgenre,
      closedCaptioning: .detail.informations.closedCaptioning,
      reviews: .detail.informations.reviews
    }')

    # Ajouter au fichier XML
    create_xml_entry "$program_details"
  done
}

# Fonction pour créer une entrée XML
create_xml_entry() {
  local details="$1"
  
  # Écrire dans le fichier XML avec xmlstarlet
  xmlstarlet ed -s "/epg" -t -n "programme" -i "/epg/programme[last()]" -t -n "title" -v "$(echo "$details" | jq -r '.title')" \
    -i "/epg/programme[last()]" -t -n "subtitle" -v "$(echo "$details" | jq -r '.subtitle')" \
    -i "/epg/programme[last()]" -t -n "description" -v "$(echo "$details" | jq -r '.description')" \
    -i "/epg/programme[last()]" -t -n "season" -v "$(echo "$details" | jq -r '.season')" \
    -i "/epg/programme[last()]" -t -n "episode" -v "$(echo "$details" | jq -r '.episode')" \
    -i "/epg/programme[last()]" -t -n "genre" -v "$(echo "$details" | jq -r '.genre')" \
    -o "$OUTPUT_XML"
}

# Init XML
echo "<epg>" > "$OUTPUT_XML"

# Lire les IDs des chaînes depuis le fichier channels.txt
if [[ ! -f "$CHANNELS_FILE" || ! -s "$CHANNELS_FILE" ]]; then
  echo "Le fichier '$CHANNELS_FILE' n'existe pas ou est vide."
  exit 1
fi

while IFS= read -r CHANNEL_ID; do
  echo "Traitement de la chaîne ID : $CHANNEL_ID"
  
  # Récupérer la liste des programmes pour cette chaîne
  program_list=$(get_program_list "$CHANNEL_ID" "$DATE")

  if [[ -z "$program_list" ]]; then
    echo "Aucun programme trouvé pour la chaîne ID : $CHANNEL_ID"
    continue
  fi

  if $ENABLE_DETAILS; then
    fetch_details $program_list
  fi
done < "$CHANNELS_FILE"


# Terminer le fichier XML
echo "</epg>" >> "$OUTPUT_XML"

echo "Fichier EPG généré : $OUTPUT_XML"
