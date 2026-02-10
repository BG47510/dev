#!/bin/bash

# Aller au répertoire du script
cd "$(dirname "$0")" || exit 1

epg_count=0
echo "─── DESCARGANDO EPGs ───"

# Lecture des URL
while IFS=, read -r epg; do
    ((epg_count++))
    
    # Définir un nom de fichier temporaire
    temp_file="EPG_temp${epg_count}.xml"
    gz_file="EPG_temp${epg_count}.xml.gz"

    if [[ "${epg##*.}" == "gz" ]]; then
        echo " │ Descargando y descomprimiendo: $epg"
        wget -O "$gz_file" -q "$epg"
        
        if [ ! -s "$gz_file" ]; then
            echo " └─► ❌ ERROR: El archivo descargado está vacío o no se descargó correctamente."
            continue
        fi
        
        if ! gzip -t "$gz_file" 2>/dev/null; then
            echo " └─► ❌ ERROR: El archivo no es un gzip válido."
            continue
        fi
        
        gzip -d -f "$gz_file"
    else
        echo " │ Descargando: $epg"
        wget -O "$temp_file" -q "$epg"
        
        if [ ! -s "$temp_file" ]; then
            echo " └─► ❌ ERROR: El archivo descargado está vacío o no se descargó correctamente."
            continue
        fi
    fi
    
    # Ignorer la déclaration DTD si elle existe
    sed -i '/<!DOCTYPE/d' "$temp_file"

    if [ -f "$temp_file" ]; then
        listado="canales_epg${epg_count}.txt"
        echo " └─► Generando listado de canales: $listado"
        echo "# Fuente: $epg" > "$listado"
        
        # Utilisation d'XMLStarlet pour extraire des informations
        xmlstarlet sel -t -m "//channel" \
        -v "@id" -o "," \
        -v "display-name" -o "," \
        -v "icon/@src" -n "$temp_file" >> "$listado"
    fi    
done < epgs.txt

echo "─── PROCESANDO CANALES ───"

mapfile -t canales < canales.txt
for i in "${!canales[@]}"; do
    IFS=',' read -r old new logo offset <<< "${canales[$i]}"
    old="$(echo "$old" | xargs)"
    new="$(echo "$new" | xargs)"
    logo="$(echo "$logo" | xargs)"
    offset="$(echo "$offset" | xargs)"
    
    if [[ "$logo" =~ ^[+-]?[0-9]+$ ]] && [[ -z "$offset" ]]; then
        offset="$logo"
        logo=""
    fi
    canales[$i]="$old,$new,$logo,$offset"
done

# Lire les étiquettes depuis variables.txt
etiquetas_sed=""
if [ -f variables.txt ]; then
    sufijos=$(grep "display-name=" variables.txt | cut -d'=' -f2 | sed 's/, /,/g')
    IFS=',' read -r -a array_etiquetas <<< "$sufijos"
    
    linea_ins=3
    for etiq in "${array_etiquetas[@]}"; do
        etiq_clean=$(echo "$etiq" | xargs)
        if [ -n "$etiq_clean" ]; then
            etiquetas_sed="${etiquetas_sed}${linea_ins}i\  <display-name>${new} ${etiq_clean}</display-name>\n"
            ((linea_ins++))
        fi
    done
fi

# Création du fichier temporaire pour les nouveaux XML
temp_file_final="temp_file_final.xml"

# Réinitialiser temp_file_final
> "$temp_file_final"

for linea in "${canales[@]}"; do
    IFS=',' read -r old new logo offset <<< "$linea"
    contar_channel="$(grep -c "channel=\"$old\"" EPG_temp.xml)"

    if [ "${contar_channel:-0}" -gt 0 ]; then
        # Extraire le logo original par si aucun nouveau logo existe
        logo_original=$(sed -n "/<channel id=\"${old}\">/,/<\/channel>/p" EPG_temp.xml | grep "<icon src" | head -1 | sed 's/^[[:space:]]*//')
        
        logo_final=""
        if [ -n "$logo" ]; then
            logo_final="    <icon src=\"${logo}\" />"
        else
            logo_final="    $logo_original"
        fi

        echo "  <channel id=\"${new}\">" >> "$temp_file_final"
        if [ -f variables.txt ]; then
            for etiq in "${array_etiquetas[@]}"; do
                etiq_clean=$(echo "$etiq" | xargs)
                if [ -n "$etiq_clean" ]; then
                    echo "    <display-name>${new} ${etiq_clean}</display-name>" >> "$temp_file_final"
                fi
            done
        else
            echo "    <display-name>${new}</display-name>" >> "$temp_file_final"
        fi
        
        # Ajouter le logo final
        [ -n "$logo_final" ] && echo "$logo_final" >> "$temp_file_final"
        echo '  </channel>' >> "$temp_file_final"

        # Gestion des programmes directement
        sed -n "/<programme.*\"${old}\"/,/<\/programme>/p" EPG_temp.xml >> "$temp_file_final"
        
        # Supprimer l'attribut channel et ajuster les balises dans temp_file_final
        sed -i "s# channel=\"$old\"##g" "$temp_file_final"
    else
        echo "        Canal ignoré: $old ··· $contar_channel correspondances"
    fi
done

echo "─── LIMITES TEMPORALES ET ACCUMULATION ───"

# Ajout du fichier accumulé à temp_file_final
if [ -f epg_acumulado.xml ]; then
    echo " Récupération des programmes depuis epg_acumulado.xml..."
    sed -n '/<programme/,/<\/programme>/p' epg_acumulado.xml >> "$temp_file_final"
fi

# Gestion des jours depuis variables.txt
dias_pasados=$(grep "dias-pasados=" variables.txt | cut -d'=' -f2 | xargs)
dias_pasados=${dias_pasados:-0}
dias_futuros=$(grep "dias-futuros=" variables.txt | cut -d'=' -f2 | xargs)
dias_futuros=${dias_futuros:-99}

# Calcul des dates limites
fecha_corte_pasado=$(date -d "$dias_pasados days ago 00:00" +"%Y%m%d%H%M%S")
fecha_corte_futuro=$(date -d "$dias_futuros days 02:00" +"%Y%m%d%H%M%S")

echo " Nettoyage passé : Maintenir depuis $fecha_corte_pasado ($dias_pasados jours)"
echo " Nettoyage futur : Limiter jusqu'à $fecha_corte_futuro ($dias_futuros jours)"

# Validation finale du fichier XML
if xmlstarlet val -e "$temp_file_final"; then
    echo " │ Le fichier XML est conforme."
    cp "$temp_file_final" epg_acumulado.xml
    echo " epg_acumulado.xml mis à jour pour la prochaine session."
else
    echo " ❌ ERREUR : Des problèmes de structure XML ont été détectés."
    xmlstarlet val -e "$temp_file_final" 2>&1 | sed 's/^/   /'
fi

# Création de miEPG.xml
{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo "<tv generator-info-name=\"miEPG v3.6\" generator-info-url=\"https://github.com/davidmuma/miEPG\">"
    
    # Insérer les canaux (avec variantes et logos traités précédemment)
    [ -f EPG_temp1.xml ] && cat EPG_temp1.xml
    
    # Insérer les programmes (nouveaux + anciens filtrés)
    [ -f "$temp_file_final" ] && cat "$temp_file_final"
    
    echo '</tv>'
} > miEPG.xml

# Suppression des lignes vides et des doublons
awk 'NF' miEPG.xml | awk '!seen[$0]++' > miEPG_clean.xml

# Remplacer l'ancien fichier par le nouveau nettoyé
mv miEPG_clean.xml miEPG.xml

# Suppression des fichiers temporaires
rm -f EPG_temp* 2>/dev/null
rm -f "$temp_file_final"
echo "─── PROCESO FINALIZADO ───"
