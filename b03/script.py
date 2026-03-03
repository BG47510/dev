import os
import requests
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta
import gzip
import shutil
import io

# Récupérer le répertoire du script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CHANNELS_FILE = os.path.join(SCRIPT_DIR, "channels.txt")
URLS_FILE = os.path.join(SCRIPT_DIR, "urls.txt")
OUTPUT_FILE = os.path.join(SCRIPT_DIR, "epg.xml.gz")
TEMP_DIR = os.path.join(SCRIPT_DIR, "temp_epg")

os.makedirs(TEMP_DIR, exist_ok=True)

# Chargement du mapping
ID_MAP = {}
CHANNEL_IDS = []

with open(CHANNELS_FILE, 'r') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        try:
            old_id, new_id = map(str.strip, line.split(',', 1))
            if old_id and new_id:
                ID_MAP[old_id] = new_id
                CHANNEL_IDS.append(old_id)
        except ValueError:
            print(f"Erreur de format dans la ligne : {line}.")

# Paramètres temporels
NOW = datetime.now().strftime("%Y%m%d%H%M")
LIMIT = (datetime.now() + timedelta(days=1)).strftime("%Y%m%d%H%M")

print("--- Démarrage du traitement ---")

CHANNELS_FILLED = {}
count = 0

with open(URLS_FILE, 'r') as f:
    URLs = [line.strip() for line in f if line.strip() and not line.startswith('#')]

for url in URLs:
    count += 1
    print(f"Source {count} : {url}")

    response = requests.get(url, timeout=10)
    if response.status_code != 200:
        continue

    content = io.BytesIO(response.content)
    
    # Décompression conditionnelle
    if url.endswith('.gz'):
        content = gzip.GzipFile(fileobj=content)

    try:
        tree = ET.parse(content)
        root = tree.getroot()

        ids_in_source = [channel.attrib['id'] for channel in root.findall('channel')]
        found_new_content = False

        for old_id in ids_in_source:
            new_id = ID_MAP.get(old_id)
            if new_id and new_id not in CHANNELS_FILLED:
                CHANNELS_FILLED[new_id] = True
                found_new_content = True
        
        # Supprimer les éléments non pertinents
        to_remove = []
        if found_new_content:
            for channel in root.findall('channel'):
                if all(channel.attrib.get('id') != old_id for old_id in ids_in_source):
                    to_remove.append(channel)

            for channel in to_remove:
                root.remove(channel)

            to_remove_programmes = []
            for programme in root.findall('programme'):
                stop = programme.attrib['stop']
                start = programme.attrib['start']
                if (start > LIMIT) or (stop < NOW):
                    to_remove_programmes.append(programme)

            for programme in to_remove_programmes:
                root.remove(programme)

            tree.write(os.path.join(TEMP_DIR, f'src_{count}.xml'), encoding='utf-8', xml_declaration=True)
        else:
            print("  [i] Aucun nouveau canal requis dans cette source.")
            open(os.path.join(TEMP_DIR, f'src_{count}.xml'), 'w').close()
            
    except ET.ParseError as e:
        print(f"Erreur lors du parsing de la source {url} : {e}")

# Assemblage final
print("Assemblage du fichier final...")

with gzip.open(OUTPUT_FILE, 'wt', encoding='utf-8') as output_file:
    output_file.write('<?xml version="1.0" encoding="UTF-8"?>\n<tv>\n')

    # Liste pour stocker les chaînes à écrire
    output_lines = []

    for src in os.listdir(TEMP_DIR):
        if src.startswith("src_"):
            src_file_path = os.path.join(TEMP_DIR, src)
            if os.path.isfile(src_file_path) and os.path.getsize(src_file_path) > 0:
                try:
                    tree = ET.parse(src_file_path)
                    root = tree.getroot()
                    
                    # Écriture des canaux
                    for channel in root.findall('channel'):
                        old_id = channel.attrib.get('id')
                        if old_id in ID_MAP:
                            channel.attrib['id'] = ID_MAP[old_id]
                            output_lines.append(ET.tostring(channel, encoding='utf-8', xml_declaration=False).decode())
                except ET.ParseError as e:
                    print(f"Erreur lors du parsing de {src_file_path} : {e}")

    # Écriture des programmes
    seen = {}
    for src in os.listdir(TEMP_DIR):
        if src.startswith("src_"):
            src_file_path = os.path.join(TEMP_DIR, src)
            if os.path.isfile(src_file_path) and os.path.getsize(src_file_path) > 0:
                try:
                    tree = ET.parse(src_file_path)
                    root = tree.getroot()
                    for programme in root.findall('programme'):
                        old_id = programme.attrib['channel']
                        if old_id in ID_MAP:
                            new_id = ID_MAP[old_id]
                            programme.attrib['channel'] = new_id
                            key = f"{new_id}_{programme.attrib['start']}"
                            if key not in seen:
                                seen[key] = True
                                output_lines.append(ET.tostring(programme, encoding='utf-8', xml_declaration=False).decode())
                except ET.ParseError as e:
                    print(f"Erreur lors du parsing de {src_file_path} : {e}")

    # Écriture de toutes les lignes à la fois (sans lignes vides)
    output_file.write('\n'.join(output_lines) + '\n')  # Ajoutez un retour à la ligne après toutes les entrées
    output_file.write('</tv>\n')  # Retour à la ligne après la fermeture de <tv>

# Nettoyage final
shutil.rmtree(TEMP_DIR)
print(f"SUCCÈS : {OUTPUT_FILE} généré.")
