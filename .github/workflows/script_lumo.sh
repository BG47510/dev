#!/usr/bin/env bash
#
# EPG – Fusion, renommage et ajustement d’un guide XMLTV
# écrit le 03‑févr‑2026
# --------------------------------------------------------------
# Prérequis :
#   - bash, wget, gzip, awk, perl, xmllint
#   - coreutils (date, sed) – sur macOS installer gdate/gsed
# --------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'                     # Séparer correctement les lignes

# --------------------------- Constantes ---------------------------
readonly REPO_URL="https://github.com/"
readonly LOG_PREFIX="│"

# --------------------------- Fonctions ---------------------------

die() {
    printf "❌ %s\n" "$*" >&2
    exit 1
}

log() {
    printf "%s %s\n" "$LOG_PREFIX" "$*"
}

# Vérifie qu’une commande indispensable est disponible
require_cmd() {
    command -v "$1" >/dev/null || die "Commande requise introuvable : $1"
}

# Téléchargement d’un fichier (gzip ou non) avec contrôle d’erreur
download_epg() {
    local url=$1 dest=$2
    log "Téléchargement : $url"
    if ! wget -q -O "$dest" "$url"; then
        log "❌ Échec du téléchargement de $url"
        return 1
    fi
    # Si c’est un .gz, vérifier l’intégrité
    if [[ "$dest" == *.gz ]]; then
        if ! gzip -t "$dest" 2>/dev/null; then
            log "❌ $dest n’est pas un gzip valide"
            return 1
        fi
        gzip -d -f "$dest"
    fi
    return 0
}

# Extraction des informations de chaîne depuis un XML
extract_channels() {
    local xml=$1 out=$2
    awk '
    /<channel / { match($0, /id="([^"]+)"/, a); id=a[1]; name=""; logo="" }
    /<display-name[^>]*>/ && name=="" {
        match($0, /<display-name[^>]*>([^<]+)<\/display-name>/, a); name=a[1]
    }
    /<icon src/ { match($0, /src="([^"]+)"/, a); logo=a[1] }
    /<\/channel>/ { print id "," name "," logo }
    ' "$xml" >> "$out"
}

# Validation du XML final avec xmllint
validate_xml() {
    local file=$1
    if ! xmllint --noout "$file" 2>validation.err; then
        log "❌ Validation XML échouée :"
        cat validation.err >&2
        rm -f validation.err
        return 1
    fi
    rm -f validation.err
    return 0
}

# Nettoyage des fichiers temporaires
cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

# --------------------------- Pré‑checks ---------------------------
require_cmd wget
require_cmd gzip
require_cmd awk
require_cmd perl
require_cmd xmllint
require_cmd date   # sur macOS remplacer par gdate si nécessaire
require_cmd sed    # sur macOS remplacer par gsed si nécessaire

# --------------------------- Boucle de téléchargement ---------------------------
TMPDIR=$(mktemp -d)
log "Répertoire temporaire créé : $TMPDIR"

# Vérification de l'existence des fichiers avant de les copier
[[ -f epgs.txt ]] || die "Fichier epgs.txt introuvable."
[[ -f choix.txt ]] || die "Fichier choix.txt introuvable."

# Copies sécurisées des listes d’entrée (on ne modifie jamais les originaux)
cp epgs.txt "$TMPDIR/epgs.lst"
cp choix.txt "$TMPDIR/choix.lst"

epg_idx=0
while IFS=, read -r epg_url; do
    ((epg_idx++))
    tmp_file="$TMPDIR/EPG_${epg_idx}.xml"

    # Téléchargement (gère .gz automatiquement)
    if ! download_epg "$epg_url" "$tmp_file"; then
        log "⚠️  Passage au prochain EPG"
        continue
    fi

    # Extraction des chaînes et agrégation du XML complet
    liste="choix_epg${epg_idx}.txt"
    printf "# Source: %s\n" "$epg_url" > "$liste"
    extract_channels "$tmp_file" "$liste"
    cat "$tmp_file" >> "$ALL_XML"
done < "$TMPDIR/epgs.lst"

log "─── FIN DES TÉLÉCHARGEMENTS ───"

# --------------------------- Variables temporaires ---------------------------

# Suppression des lignes vides
# Modifiez selon l'environnement (Linux ou macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' '/^ *$/d' "$TMPDIR/epgs.lst" "$TMPDIR/choix.lst"  # Pour macOS
else
    sed -i '/^ *$/d' "$TMPDIR/epgs.lst" "$TMPDIR/choix.lst"  # Pour Linux
fi

# Fichiers agrégés
ALL_XML="$TMPDIR/EPG_all.xml"
CHANNEL_LIST="$TMPDIR/channel_list.txt"
"$ALL_XML"
"$CHANNEL_LIST"

# --------------------------- Lecture du mapping de chaînes ---------------------------
mapfile -t choix < "$TMPDIR/choix.lst"

# Normalisation du tableau (suppression d’espaces superflus)
for i in "${!choix[@]}"; do
    IFS=',' read -r old new logo offset <<< "${choix[$i]}"
    old=$(printf '%s' "$old" | xargs)
    new=$(printf '%s' "$new" | xargs)
    logo=$(printf '%s' "$logo" | xargs)
    offset=$(printf '%s' "$offset" | xargs)

    # Cas où le champ « logo » contient en réalité un offset
    if [[ "$logo" =~ ^[+-]?[0-9]+$ ]] && [[ -z "$offset" ]]; then
        offset="$logo"
        logo=""
    fi
    choix=("$old,$new,$logo,$offset")
done

# --------------------------- Traitement des chaînes ---------------------------
# --------------------------- Traitement des chaînes ---------------------------
CHANNEL_XML="$TMPDIR/EPG_channels.xml"
PROGRAM_XML="$TMPDIR/EPG_programmes.xml"
"$CHANNEL_XML"
"$PROGRAM_XML"

for linea in "${choix[@]}"; do
    IFS=',' read -r old new logo offset <<< "$linea"
    count=$(grep -c "channel=\"$old\"" "$ALL_XML")

    if (( count == 0 )); then
        log "⏭️  Chaîne ignorée : $old (aucune correspondance)"
        continue
    fi

    # ------------------------------------------------------------------
    # 1️⃣  Construction du bloc <channel>
    # ------------------------------------------------------------------
    {
        printf '  <channel id="%s">\n' "$new"
        if [[ -f variables.txt ]]; then
            suffixes=$(grep "display-name=" variables.txt | cut -d'=' -f2 | tr -d ' ')
            IFS=',' read -ra tags <<< "$suffixes"
            for tag in "${tags[@]}"; do
                [[ -n "$tag" ]] && printf '    <display-name>%s %s</display-name>\n' "$new" "$tag"
            done
        else
            printf '    <display-name>%s</display-name>\n' "$new"
        fi

        if [[ -n "$logo" ]]; then
            printf '    <icon src="%s" />\n' "$logo"
        else
            orig_logo=$(sed -n "/<channel id=\"$old\">/,/<\/channel>/p" "$ALL_XML" |
                        grep "<icon src" | head -1 | sed 's/^[[:space:]]*//')
            [[ -n "$orig_logo" ]] && printf '    %s\n' "$orig_logo"
        fi
        echo '  </channel>'
    } >> "$CHANNEL_XML"

    # ------------------------------------------------------------------
    # 2️⃣  Extraction et adaptation des <programme>
    # ------------------------------------------------------------------
    prog_tmp="$TMPDIR/prog_${old}.xml"
    sed -n "/<programme.*\"${old}\"/,/<\/programme>/p" "$ALL_XML" > "$prog_tmp"

    # Suppression de l’attribut channel et insertion du nouveau nom
    sed -i '' "s/ channel=\"${old}\"/ channel=\"${new}\"/g" "$prog_tmp"

    if [[ "$offset" =~ ^[+-]?[0-9]+$ ]]; then
        log "🕒  Application d’un offset de $offset h sur $new"
        export OFFSET_SEC=$(( offset * 3600 ))
        export NEW_CHAN="$new"
        perl -MDate::Parse -MDate::Format -i'' -pe '
            if (/<programme start="([^"]+) ([^"]+)" stop="([^"]+) ([^"]+)" channel="[^"]+">/) {
                my ($s, $tzs, $e, $tze) = ($1, $2, $3, $4);
                my $s_fmt = sprintf("%04d-%02d-%02d %02d:%02d:%02d", 
                                    substr($s, 0, 4), substr($s, 4, 2), substr($s, 6, 2),
                                    substr($s, 8, 2), substr($s, 10, 2), substr($s, 12, 2));
                my $e_fmt = sprintf("%04d-%02d-%02d %02d:%02d:%02d", 
                                    substr($e, 0, 4), substr($e, 4, 2), substr($e, 6, 2),
                                    substr($e, 8, 2), substr($e, 10, 2), substr($e, 12, 2));
                my $s_ts = str2time("$s_fmt $tzs") + $ENV{OFFSET_SEC};
                my $e_ts = str2time("$e_fmt $tze") + $ENV{OFFSET_SEC};
                my $s_new = time2str("%Y%m%d%H%M%S $tzs", $s_ts);
                my $e_new = time2str("%Y%m%d%H%M%S $tze", $e_ts);
                s/<programme start="[^"]+" stop="[^"]+" channel="[^"]+">/
                  "<programme start=\"$s_new\" stop=\"$e_new\" channel=\"$ENV{NEW_CHAN}\">"/e;
            }
        ' "$prog_tmp"
    fi

    cat "$prog_tmp" >> "$PROGRAM_XML"
    rm -f "$prog_tmp"
done

log "─── FIN DU TRAITEMENT DES CHAÎNES ───"

# --------------------------- Gestion des limites temporelles ---------------------------
# Valeurs par défaut si variables.txt est absent ou incomplet
jours_avant=$(grep "^jours-avant=" variables.txt 2>/dev/null | cut -d'=' -f2 | xargs || echo 0)
jours_venir=$(grep "^jours-venir=" variables.txt 2>/dev/null | cut -d'=' -f2 | xargs || echo 99)

# Compatibilité GNU date – sur macOS remplacer par gdate
cutoff_past=$(date -d "$jours_avant days ago 00:00" +"%Y%m%d%H%M%S")
cutoff_future=$(date -d "$jours_venir days 02:00" +"%Y%m%d%H%M%S")

log "Limite avant : $cutoff_past  (‑$jours_avant jrs)"
log "Limite venir : $cutoff_future (+$jours_venir jrs)"

# Filtrage final avec Perl (déduplication + suppression hors‑limites)
perl -i -ne '
    BEGIN {
        $past   = "'"$cutoff_past"'";
        $future = "'"$cutoff_future"'";
        %seen   = ();
        $kept   = $removed_past = $removed_future = $duplicates = 0;
    }
    if (/<programme start="(\d{14})[^"]+" stop="[^"]+" channel="([^"]+)">/) {
        $start = $1; $chan = $2;
        if ($start < $past)          { $removed_past++;   next; }
        if ($start > $future)        { $removed_future++; next; }
        my $key = "$start-$chan";
        if ($seen{$key}++)           { $duplicates++;    next; }
        $kept++;
    }
    print;
    END {
        warn " ─► Ajouté : $kept\n";
        warn " ─► Avant supprimé : $removed_past\n";
        warn " ─► Venir supprimé : $removed_future\n";
        warn " ─► Doublons éliminés : $duplicates\n";
    }
' "$PROGRAM_XML"

# --------------------------- Assemblage final du XML ---------------------------
OUTPUT="epg.xml"
{
    printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '<tv generator-info-name="epg v1.0" generator-info-url="%s">\n' "$REPO_URL"
    cat "$CHANNEL_XML"
    cat "$PROGRAM_XML"
    printf '</tv>\n'
} > "$OUTPUT"

# --------------------------- Validation finale ---------------------------
if validate_xml "$OUTPUT"; then
    log "✅  Le fichier XML est valide."
    nb_chan=$(grep -c "<channel " "$OUTPUT")
    nb_prog=$(grep -c "<programme " "$OUTPUT")
    log "📺  Chaînes : $nb_chan | Programmes : $nb_prog"
    cp "$OUTPUT" epg_archive.xml
    log "🔁  epg_archive.xml mis à jour pour la prochaine exécution."
else
    log "❗  Le XML comporte des erreurs – le fichier n’a pas été sauvegardé."
fi

log "─── PROCESSUS TERMINÉ ───"
