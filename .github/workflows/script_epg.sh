#!/usr/bin/env bash
set -euo pipefail

########################################
# 0. Fonctions utilitaires
########################################

log() { echo -e "$1"; }

die() { echo "❌ $1" >&2; exit 1; }

clean_temp() {
    rm -f EPG_temp* canales_epg*.txt 2>/dev/null || true
}

########################################
# 1. Lecture des variables
########################################

load_variables() {
    dias_pasados=0
    dias_futuros=99
    display_suffixes=()

    [[ ! -f variables.txt ]] && return

    while IFS='=' read -r key value; do
        value=$(echo "$value" | xargs)
        case "$key" in
            dias-pasados) dias_pasados="${value:-0}" ;;
            dias-futuros) dias_futuros="${value:-99}" ;;
            display-name)
                value=${value//, /,}
                IFS=',' read -r -a display_suffixes <<< "$value"
                ;;
        esac
    done < variables.txt
}

########################################
# 2. Téléchargement et fusion des EPG
########################################

download_and_merge_epg() {
    log "─── TÉLÉCHARGEMENT EPGs ───"
    
    # Vérifie si le fichier epgs.txt existe
    if [[ ! -f epgs.txt ]]; then
        log "Erreur : le fichier epgs.txt est manquant."
        exit 1
    fi

    > EPG_temp.xml
    epg_count=0

    while IFS=, read -r epg; do
        epg=$(echo "$epg" | xargs)
        [[ -z "$epg" ]] && continue

        ((epg_count++))
        extension="${epg##*.}"
        temp="EPG_temp_${epg_count}.xml"

        if [[ "$extension" == "gz" ]]; then
            log " │ Téléchargement et décompression: $epg"
            if wget -q -O "${temp}.gz" "$epg"; then
                log " │ Téléchargement réussi: $epg"
            else
                log " │ Échec du téléchargement: $epg"
                continue
            fi

            if gzip -df "${temp}.gz"; then
                log " │ Décompression réussie: ${temp}.gz"
            else
                log " │ Échec de la décompression: ${temp}.gz"
                continue
            fi
        else
            log " │ Téléchargement: $epg"
            if wget -q -O "$temp" "$epg"; then
                log " │ Téléchargement réussi: $epg"
            else
                log " │ Échec du téléchargement: $epg"
                continue
            fi
        fi

        [[ ! -s "$temp" ]] && continue

        # Extraction des chaînes
        listado="canales_epg${epg_count}.txt"
        {
            echo "# Source: $epg"
            awk '
                /<channel / {
                    match($0, /id="([^"]+)"/, a); id=a[1]; name=""; logo="";
                }
                /<display-name[^>]*>/ && name == "" {
                    match($0, /<display-name[^>]*>([^<]+)<\/display-name>/, a);
                    name=a[1];
                }
                /<icon src/ {
                    match($0, /src="([^"]+)"/, a); logo=a[1];
                }
                /<\/channel>/ {
                    output = id "," name;
                    if (length(logo) > 0) {
                        output = output "," logo;
                    }
                    print output;
                }
            ' "$temp"
        } > "$listado"

        cat "$temp" >> EPG_temp.xml
    done < epgs.txt

    # Vérification de la validité du fichier XML avant modification
    if xmllint --noout EPG_temp.xml 2>/dev/null; then
        sed -i 's/></>\n</g' EPG_temp.xml
    else
        log "Erreur : EPG_temp.xml n'est pas un fichier XML bien formé."
        exit 1
    fi
}

########################################
# 3. Lecture et normalisation des chaînes
########################################

load_channels() {
    mapfile -t canales < canales.txt

    for i in "${!canales[@]}"; do
        IFS=',' read -r old new logo offset <<< "${canales[$i]}"

        old=$(echo "$old" | xargs)
        new=$(echo "$new" | xargs)
        logo=$(echo "$logo" | xargs)
        offset=$(echo "$offset" | xargs)

        if [[ "$logo" =~ ^[+-]?[0-9]+$ ]] && [[ -z "$offset" ]]; then
            offset="$logo"
            logo=""
        fi

        canales[$i]="$old,$new,$logo,$offset"
    done
}

########################################
# 4. Reconstruction des chaînes et programmes
########################################

process_channels() {
    > EPG_temp1.xml
    > EPG_temp2.xml

    for linea in "${canales[@]}"; do
        IFS=',' read -r old new logo offset <<< "$linea"
        [[ -z "$old" || -z "$new" ]] && continue

        contar=$(grep -c "channel=\"$old\"" EPG_temp.xml || true)
        (( contar == 0 )) && continue

        # Logo original
        logo_original=$(sed -n "/<channel id=\"${old}\"/,/<\/channel>/p" EPG_temp.xml \
                        | grep -o '<icon[^>]*>' | head -1 || true)

        # Logo final
        if [[ -n "$logo" ]]; then
            logo_final="    <icon src=\"$logo\" />"
        else
            logo_final="    $logo_original"
        fi

        # Nouveau bloc <channel>
        {
            echo "  <channel id=\"$new\">"
            if ((${#display_suffixes[@]} > 0)); then
                for etiq in "${display_suffixes[@]}"; do
                    etiq_clean=$(echo "$etiq" | xargs)
                    echo "    <display-name>${new} ${etiq_clean}</display-name>"
                done
            else
                echo "    <display-name>${new}</display-name>"
            fi
            echo "$logo_final"
            echo "  </channel>"
        } >> EPG_temp1.xml

        # Programmes
        sed -n "/<programme.*\"${old}\"/,/<\/programme>/p" EPG_temp.xml > EPG_temp02.xml

        sed -i "s/channel=\"$old\"/channel=\"$new\"/g" EPG_temp02.xml

        if [[ "$offset" =~ ^[+-]?[0-9]+$ ]]; then
            export OFFSET="$offset" NEW_CHANNEL="$new"
            perl -MDate::Parse -MDate::Format -i'' -pe '
                BEGIN {
                    $off = $ENV{OFFSET} * 3600;
                    $new = $ENV{NEW_CHANNEL};
                }
                if (/<programme start="([^"]+)" stop="([^"]+)" channel="([^"]+)">/) {
                    my ($s, $e) = ($1, $2);
                    my $s2 = time2str("%Y%m%d%H%M%S %z", str2time($s) + $off);
                    my $e2 = time2str("%Y%m%d%H%M%S %z", str2time($e) + $off);
                    s/start="[^"]+"/start="$s2"/;
                    s/stop="[^"]+"/stop="$e2"/;
                    s/channel="[^"]+"/channel="$new"/;
                }
            ' EPG_temp02.xml
        fi

        cat EPG_temp02.xml >> EPG_temp2.xml
    done
}

########################################
# 5. Cumul + filtrage temporel
########################################

merge_and_filter_programmes() {
    [[ -f epg_acumulado.xml ]] && \
        sed -n '/<programme/,/<\/programme>/p' epg_acumulado.xml >> EPG_temp2.xml

    fecha_pasado=$(date -d "$dias_pasados days ago 00:00" +"%Y%m%d%H%M%S")
    fecha_futuro=$(date -d "$dias_futuros days 02:00" +"%Y%m%d%H%M%S")

    perl -i -ne '
        BEGIN { 
            $min = "'$fecha_pasado'"; 
            $max = "'$fecha_futuro'"; 
            %seen=(); 
            $ok=$past=$future=$dup=0;
            $print=0;
        }
        if (/<programme start="(\d{14})[^"]*" stop="[^"]*" channel="([^"]+)">/) {
            my ($t,$c)=($1,$2);
            my $key="$t-$c";
            if ($t < $min) { $past++; $print=0; }
            elsif ($t > $max) { $future++; $print=0; }
            elsif ($seen{$key}++) { $dup++; $print=0; }
            else { $ok++; $print=1; }
        }
        print if $print;
        if (/<\/programme>/) { $print=0; }
        END {
            print STDERR " ─► Acceptés: $ok\n";
            print STDERR " ─► Passés: $past\n";
            print STDERR " ─► Futurs: $future\n";
            print STDERR " ─► Doublons: $dup\n";
        }
    ' EPG_temp2.xml
}

########################################
# 6. Construction finale
########################################

build_final_xml() {
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<tv generator-info-name="miEPG refactorisé">'
        cat EPG_temp1.xml
        cat EPG_temp2.xml
        echo '</tv>'
    } > miEPG.xml
}

########################################
# 7. Validation
########################################

validate_xml() {
    if xmllint --noout miEPG.xml 2>/dev/null; then
        log "XML valide."
        cp miEPG.xml epg_acumulado.xml
    else
        log "❌ XML invalide."
        xmllint --noout miEPG.xml 2>&1
    fi
}

########################################
# 8. Main
########################################

main() {
    clean_temp
    load_variables
    download_and_merge_epg
    load_channels
    process_channels
    merge_and_filter_programmes
    build_final_xml
    validate_xml
    clean_temp
    log "─── PROCESSUS TERMINÉ ───"
}

main
