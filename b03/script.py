import os
import requests
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta
import gzip
import shutil

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
        try:
            old_id, new_id = map(str.strip, line.split(',', 1))
            if old_id and new_id:
                ID_MAP[old_id] = new_id
                CHANNEL_IDS.append(old_id)
        except ValueError:
            print(f"Erreur de format dans la ligne : {line}. Assurez-vous qu'elle est correctement formatée.")

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
    raw_file = os.path.join(TEMP_DIR, f"raw_{count}.xml.gz" if url.endswith('.gz') else f"raw_{count}.xml")
    src_file = os.path.join(TEMP_DIR, f"src_{count}.xml")

    print(f"Source {count} : {url}")

    # Télécharger le fichier
    response = requests.get(url, timeout=10)
    if response.status_code != 200:
        print(f"Erreur de téléchargement : {response.status_code}")
        continue

    with open(raw_file, 'wb') as f:
        f.write(response.content)

    # Vérifier si c'est un fichier gzip
    if url.endswith('.gz'):
        print(f"Décompression de {raw_file}...")
        with gzip.open(raw_file, 'rb') as f_in:
            with open(raw_file[:-3], 'wb') as f_out:  # Enregistrer sans .gz
                f_out.write(f_in.read())
        raw_file = raw_file[:-3]  # Mettre à jour le nom du fichier

    # Vérifiez si le fichier est vide
    if os.path.getsize(raw_file) == 0:
        print(f"Le fichier {raw_file} est vide après décompression.")
        continue

    # Traitement XML
    try:
        tree = ET.parse(raw_file)
        root = tree.getroot()

        ids_in_source = [channel.attrib['id'] for channel in root.findall('channel')]
        found_new_content = False

        for old_id in ids_in_source:
            new_id = ID_MAP.get(old_id)
            if new_id and new_id not in CHANNELS_FILLED:
                CHANNELS_FILLED[new_id] = True
                found_new_content = True

        if found_new_content:
            for channel in root.findall('channel'):
                if all(channel.attrib.get('id') != old_id for old_id in ids_in_source):
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
    except ET.ParseError as e:
        print(f"Erreur lors du parsing de {raw_file} : {e}")

# Assemblage final
print("Assemblage du fichier final...")

with open(OUTPUT_FILE, 'w', encoding='utf-8') as output_file:
    # Ajoutez un retour à la ligne après la déclaration XML
    output_file.write('<?xml version="1.0" encoding="UTF-8"?>\n<tv>\n')

    # Canaux : Extraction et renommage
    for src in os.listdir(TEMP_DIR):
        if src.startswith("src_"):
            src_file_path = os.path.join(TEMP_DIR, src)
            if os.path.isfile(src_file_path) and os.path.getsize(src_file_path) > 0:
                try:
                    tree = ET.parse(src_file_path)
                    root = tree.getroot()
                    
                    # Seule l'écriture des canaux pertinents
                    for channel in root.findall('channel'):
                        old_id = channel.attrib.get('id')
                        if old_id in ID_MAP:  # Vérifier si l'ID est dans ID_MAP
                            channel.attrib['id'] = ID_MAP[old_id]  # Renommage
                            output_file.write(ET.tostring(channel, encoding='utf-8', xml_declaration=False).decode())
                            output_file.write('\n')  # Retour à la ligne après chaque canal
                except ET.ParseError as e:
                    print(f"Erreur lors du parsing de {src_file_path} : {e}")

    # Programmes : Dédoublonnage et renommage
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
                                output_file.write(ET.tostring(programme, encoding='utf-8', xml_declaration=False).decode())
                                output_file.write('\n')  # Retour à la ligne après chaque programme
                except ET.ParseError as e:
                    print(f"Erreur lors du parsing de {src_file_path} : {e}")

    output_file.write('</tv>\n')  # Retour à la ligne avant la fermeture de <tv>

# Nettoyage final
shutil.rmtree(TEMP_DIR)
print(f"SUCCÈS : {OUTPUT_FILE} généré.")
