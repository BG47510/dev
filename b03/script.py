import os
import requests
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta
import gzip
import shutil

# Configuration
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CHANNELS_FILE = os.path.join(SCRIPT_DIR, "channels.txt")
URLS_FILE = os.path.join(SCRIPT_DIR, "urls.txt")
OUTPUT_FILE = os.path.join(SCRIPT_DIR, "epg.xml.gz")
TEMP_DIR = os.path.join(SCRIPT_DIR, "temp_epg")

os.makedirs(TEMP_DIR, exist_ok=True)

# 1. Chargement du mapping (ID_SOURCE -> ID_DEST)
id_map = {}
with open(CHANNELS_FILE, 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'): continue
        parts = line.split(',', 1)
        if len(parts) == 2:
            id_map[parts[0].strip()] = parts[1].strip()

# 2. Paramètres temporels (Format XMLTV : YYYYMMDDHHMMSS)
now_str = datetime.now().strftime("%Y%m%d%H%M")
limit_str = (datetime.now() + timedelta(days=2)).strftime("%Y%m%d%H%M")

def download_and_clean():
    processed_channels = set()
    
    with open(URLS_FILE, 'r') as f:
        urls = [line.strip() for line in f if line.strip() and not line.startswith('#')]

    with gzip.open(OUTPUT_FILE, 'wt', encoding='utf-8') as out_f:
        out_f.write('<?xml version="1.0" encoding="UTF-8"?>\n<tv>\n')
        
        # Buffer pour stocker les programmes afin de les écrire après les channels
        programmes_buffer = []

        for idx, url in enumerate(urls, 1):
            print(f"Traitement source {idx}: {url}")
            try:
                r = requests.get(url, timeout=15, stream=True)
                r.raise_for_status()
                
                # Gestion auto de la décompression si flux gzip
                content = gzip.decompress(r.content) if url.endswith('.gz') else r.content
                root = ET.fromstring(content)

                # Traitement des chaînes
                for channel in root.findall('channel'):
                    orig_id = channel.get('id')
                    if orig_id in id_map:
                        new_id = id_map[orig_id]
                        if new_id not in processed_channels:
                            channel.set('id', new_id)
                            out_f.write(ET.tostring(channel, encoding='unicode'))
                            processed_channels.add(new_id)

                # Traitement des programmes
                for prog in root.findall('programme'):
                    orig_id = prog.get('channel')
                    if orig_id in id_map:
                        start = prog.get('start')
                        stop = prog.get('stop')
                        
                        # Filtre temporel (simple string compare)
                        if stop[:12] >= now_str and start[:12] <= limit_str:
                            prog.set('channel', id_map[orig_id])
                            out_f.write(ET.tostring(prog, encoding='unicode'))

            except Exception as e:
                print(f"Erreur sur {url}: {e}")

        out_f.write('</tv>')

if __name__ == "__main__":
    print("--- Démarrage de la génération EPG ---")
    download_and_clean()
    if os.path.exists(TEMP_DIR):
        shutil.rmtree(TEMP_DIR)
    print(f"Terminé. Fichier généré : {OUTPUT_FILE}")
