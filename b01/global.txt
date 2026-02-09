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
            echo " └─► ❌ ERROR: El archivo descargado está vacío o no se descargó correctamente"
            continue
        fi
        
        if ! gzip -t "$gz_file" 2>/dev/null; then
            echo " └─► ❌ ERROR: El archivo no es un gzip válido"
            continue
        fi
        
        gzip -d -f "$gz_file"
    else
        echo " │ Descargando: $epg"
        wget -O "$temp_file" -q "$epg"
        
        if [ ! -s "$temp_file" ]; then
            echo " └─► ❌ ERROR: El archivo descargado está vacío o no se descargó correctamente"
            continue
        fi
    fi
    
    if [ -f "$temp_file" ]; then
        listado="canales_epg${epg_count}.txt"
        echo " └─► Generando listado de canales: $listado"
        echo "# Fuente: $epg" > "$listado"
        
        # Utilisation d'XMLStarlet pour extraire des informations
        xmlstarlet sel -t -m "//channel" \
        -v "@id" -o "," \
        -v "display-name" -o "," \
        -v "icon/@src" -n "$temp_file" >> "$listado"
        
        # Optionnel : Manipulation supplémentaire si nécessaire
    fi    
done < epgs.txt

