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
OUTPUT_FILE = os.path.join(SCRIPT_DIR, "epg.xml.gz")  # Changer l'extension
TEMP_DIR = os.path.join(SCRIPT_DIR, "temp_epg")


# ... (votre code de chargement du mapping)

for url in URLs:
    count += 1
    print(f"Source {count} : {url}")

    response = requests.get(url, timeout=10)
    if response.status_code != 200:
        continue

    # Utilisation de io.BytesIO pour traiter le contenu en mémoire
    content = io.BytesIO(response.content)

    # Si c'est un GZIP, on le décompresse "à la volée"
    if url.endswith('.gz'):
        content = gzip.GzipFile(fileobj=content)

    try:
        # ElementTree peut lire directement depuis l'objet 'content'
        tree = ET.parse(content)
        root = tree.getroot()
        
        # ... (le reste de votre logique de filtrage)










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
    print(f"Source {count} : {url}")

    response = requests.get(url, timeout=10)
    if response.status_code != 200:
        continue

    # Utilisation de io.BytesIO pour traiter le contenu en mémoire
    content = io.BytesIO(response.content)

    # Si c'est un GZIP, on le décompresse "à la volée"
    if url.endswith('.gz'):
        content = gzip.GzipFile(fileobj=content)

    try:
        # ElementTree peut lire directement depuis l'objet 'content'
        tree = ET.parse(content)
        root = tree.getroot()

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

with gzip.open(OUTPUT_FILE, 'wt', encoding='utf-8') as output_file:  # Ouvrir un fichier gzip en mode texte
    # Ajoutez un retour à la ligne après la déclaration XML et après <tv>
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
                except ET.ParseError as e:
                    print(f"Erreur lors du parsing de {src_file_path} : {e}")

    output_file.write('</tv>\n')  # Retour à la ligne après la fermeture de <tv>

# Nettoyage final
shutil.rmtree(TEMP_DIR)
print(f"SUCCÈS : {OUTPUT_FILE} généré.")
