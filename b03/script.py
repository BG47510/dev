import os
import requests
import xml.etree.ElementTree as ET
from datetime import datetime
import gzip
import io

# Configuration
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CHANNELS_FILE = os.path.join(SCRIPT_DIR, "channels.txt")
URLS_FILE = os.path.join(SCRIPT_DIR, "urls.txt")
OUTPUT_FILE = os.path.join(SCRIPT_DIR, "epg.xml.gz")

# 1. Chargement du mapping (ID_SOURCE -> ID_DEST)
id_map = {}
if os.path.exists(CHANNELS_FILE):
    with open(CHANNELS_FILE, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'): continue
            parts = line.split(',', 1)
            if len(parts) == 2:
                id_map[parts[0].strip()] = parts[1].strip()

def download_and_parse(url):
    print(f"Téléchargement de : {url}")
    try:
        r = requests.get(url, timeout=30)
        r.raise_for_status()
        content = r.content
        
        # Décompression si c'est du GZIP
        if url.endswith('.gz') or content[:2] == b'\x1f\x8b':
            content = gzip.decompress(content)
            
        return ET.fromstring(content)
    except Exception as e:
        print(f"Erreur lors du traitement de {url}: {e}")
        return None

def run():
    if not os.path.exists(URLS_FILE):
        print(f"Erreur: {URLS_FILE} introuvable.")
        return

    with open(URLS_FILE, 'r') as f:
        urls = [line.strip() for line in f if line.strip() and not line.startswith('#')]

    processed_channels = set()
    
    print(f"--- Démarrage de la génération ---")
    
    # On prépare le nouveau fichier XML
    new_root = ET.Element("tv")
    new_root.set("generator-info-name", "MonGenerateurEPG")

    for url in urls:
        root = download_and_parse(url)
        if root is None: continue

        # 1. Extraire les chaînes (channels)
        for channel in root.findall('channel'):
            orig_id = channel.get('id')
            if orig_id in id_map:
                new_id = id_map[orig_id]
                if new_id not in processed_channels:
                    channel.set('id', new_id)
                    new_root.append(channel)
                    processed_channels.add(new_id)

        # 2. Extraire les programmes
        for prog in root.findall('programme'):
            orig_id = prog.get('channel')
            if orig_id in id_map:
                prog.set('channel', id_map[orig_id])
                new_root.append(prog)

    # Sauvegarde compressée
    print(f"Écriture du fichier : {OUTPUT_FILE}")
    tree = ET.ElementTree(new_root)
    with gzip.open(OUTPUT_FILE, 'wb') as f:
        tree.write(f, encoding='utf-8', xml_declaration=True)

if __name__ == "__main__":
    run()
    print(f"--- Terminé ---")
