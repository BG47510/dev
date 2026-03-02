import os
import requests
import xml.etree.ElementTree as ET
import csv
from datetime import datetime, timedelta

# Récupérer le répertoire du script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CHANNELS_FILE = os.path.join(SCRIPT_DIR, "channels.txt")
URLS_FILE = os.path.join(SCRIPT_DIR, "urls.txt")
OUTPUT_FILE = os.path.join(SCRIPT_DIR, "epg.xml")
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
        old_id, new_id = map(str.strip, line.split(',', 1))
        if old_id and new_id:
            ID_MAP[old_id] = new_id
            CHANNEL_IDS.append(old_id)

# Paramètres temporels
NOW = datetime.now().strftime("%Y%m%d%H%M")
LIMIT = (datetime.now() + timedelta(days=1)).strftime("%Y%m%d%H%M")

print("--- Démarrage du traitement ---")

# Récupération et filtrage
CHANNELS_FILLED = {}
count = 0

with open(URLS_FILE, 'r') as f:
    URLs = [line.strip() for line in f if line.strip() and not line.startswith('#')]

for url in URLs:
    count += 1
    raw_file = os.path.join(TEMP_DIR, f"raw_{count}.xml")
    src_file = os.path.join(TEMP_DIR, f"src_{count}.xml")

    print(f"Source {count} : {url}")

    # Téléchargement des fichiers
    response = requests.get(url, timeout=10)
    if url.endswith('.gz'):
        with open(raw_file, 'wb') as f:
            f.write(response.content)
        os.system(f"gunzip {raw_file}")  # décompression
    else:
        with open(raw_file, 'wb') as f:
            f.write(response.content)

    # Traitement XML
    if os.path.getsize(raw_file) > 0:
        tree = ET.parse(raw_file)
        root = tree.getroot()
        ids_in_source = [channel.attrib['id'] for channel in root.findall('channel')]
        xpath_filter = []
        found_new_content = False

        for old_id in ids_in_source:
            new_id = ID_MAP.get(old_id)
            if new_id and new_id not in CHANNELS_FILLED:
                xpath_filter.append(f"@id='{old_id}' or @channel='{old_id}'")
                CHANNELS_FILLED[new_id] = True
                found_new_content = True

        if found_new_content:
            for channel in root.findall('channel'):
                if not any(eval(x) for x in xpath_filter):
                    root.remove(channel)

            for programme in root.findall('programme'):
                stop = programme.attrib['stop']
                start = programme.attrib['start']
                if (start > LIMIT) or (stop < NOW):
                    root.remove(programme)

            tree.write(src_file)
        else:
            print("  [i] Aucun nouveau canal requis dans cette source.")
            open(src_file, 'w').close()  # Crée un fichier vide
        os.remove(raw_file)

# Assemblage final
print("Assemblage du fichier final...")

with open(OUTPUT_FILE, 'w', encoding='utf-8') as output_file:
    output_file.write('<?xml version="1.0" encoding="UTF-8"?><tv>')

    # Canaux : Extraction et renommage
    for src in os.listdir(TEMP_DIR):
        if src.startswith("src_"):
            src_file_path = os.path.join(TEMP_DIR, src)
            if os.path.getsize(src_file_path) > 0:
                tree = ET.parse(src_file_path)
                root = tree.getroot()
                for channel in root.findall('channel'):
                    for old in ID_MAP:
                        channel.attrib['id'] = channel.attrib['id'].replace(old, ID_MAP[old])
                    output_file.write(ET.tostring(channel, encoding='utf-8', xml_declaration=False).decode())

    # Programmes : Dédoublonnage et renommage
    seen = {}
    for src in os.listdir(TEMP_DIR):
        if src.startswith("src_"):
            src_file_path = os.path.join(TEMP_DIR, src)
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
                        output_file.write(ET.tostring(programme, encoding='utf-8', xml_declaration=False).decode())

    output_file.write('</tv>')

# Nettoyage final
import shutil
shutil.rmtree(TEMP_DIR)
# os.system(f"gzip -f {OUTPUT_FILE}")  # Optionnel : décommentez si vous voulez compresser
print(f"SUCCÈS : {OUTPUT_FILE} généré.")
