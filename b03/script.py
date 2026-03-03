import os
import requests
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta
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

# 2. Paramètres temporels
now_str = datetime.now().strftime("%Y%m%d") # On filtre par jour pour simplifier
limit_str = (datetime.now() + timedelta(days=2)).strftime("%Y%m%d")

def process_xml_stream(url, out_f, processed_channels):
    print(f"Connexion à : {url}")
    try:
        r = requests.get(url, timeout=30, stream=True)
        r.raise_for_status()
        
        # Gestion du GZIP transparent
        source = r.raw
        if url.endswith('.gz') or r.headers.get('Content-Encoding') == 'gzip':
            source = gzip.GzipFile(fileobj=r.raw)

        # Utilisation de iterparse pour ne pas charger tout en mémoire
        context = ET.iterparse(source, events=('start', 'end'))
        
        for event, elem in context:
            # Traitement des chaînes (CHANNELS)
            if event == 'end' and elem.tag == 'channel':
                orig_id = elem.get('id')
                if orig_id in id_map:
                    new_id = id_map[orig_id]
                    if new_id not in processed_channels:
                        elem.set('id', new_id)
                        out_f.write(ET.tostring(elem, encoding='unicode'))
                        processed_channels.add(new_id)
                elem.clear() # Libère la mémoire

            # Traitement des programmes (PROGRAMME)
            elif event == 'end' and elem.tag == 'programme':
                orig_id = elem.get('channel')
                if orig_id in id_map:
                    start = elem.get('start', '')
                    stop = elem.get('stop', '')
                    # Filtre temporel basique (pour éviter les programmes trop vieux)
                    if stop[:8] >= now_str and start[:8] <= limit_str:
                        elem.set('channel', id_map[orig_id])
                        out_f.write(ET.tostring(elem, encoding='unicode'))
                elem.clear() # Libère la mémoire
                
    except Exception as e:
        print(f" Erreur sur {url}: {e}")

def run():
    processed_channels = set()
    
    if not os.path.exists(URLS_FILE):
        print(f"Erreur: {URLS_FILE} introuvable.")
        return

    with open(URLS_FILE, 'r') as f:
        urls = [line.strip() for line in f if line.strip() and not line.startswith('#')]

    print(f"--- Démarrage de la génération (Mode Stream) ---")
    
    with gzip.open(OUTPUT_FILE, 'wt', encoding='utf-8') as out_f:
        out_f.write('<?xml version="1.0" encoding="UTF-8"?>\n<tv>\n')
        
        for url in urls:
            process_xml_stream(url, out_f, processed_channels)
            
        out_f.write('</tv>')

if __name__ == "__main__":
    run()
    print(f"--- Terminé. Fichier : {OUTPUT_FILE} ---")
