#!/usr/bin/env python3
import requests
import re
from pathlib import Path
import sys

# Config — fichier local (relatif au répertoire de lancement)
m3u8_path = Path("a02/frinfo.m3u8")  # chemin relatif depuis la racine du repo
backup_path = m3u8_path.with_suffix(".m3u8.bak")

# URL d'auth (inchangée)
auth_url = "https://hdfauth.ftven.fr/esi/TA?format=json&url=https://simulcast-p.ftven.fr/simulcast/France_Info/hls_monde_frinfo/index.m3u8"

# Diagnostic rapide
print("CWD:", Path.cwd())
print("Looking for:", m3u8_path.resolve())
if not m3u8_path.exists():
    sys.exit(f"Fichier introuvable : {m3u8_path.resolve()}")

# 1) Requête et extraction du "url" dans le JSON
resp = requests.get(auth_url, timeout=15)
resp.raise_for_status()
data = resp.json()
full_url = data.get("url")
if not full_url:
    sys.exit("Champ 'url' absent dans la réponse JSON.")

# 2) Extraire le nouveau token (entre domaine et /simulcast)
m_new = re.search(r"https?://[^/]+/([^/]+)/simulcast/", full_url)
if not m_new:
    sys.exit("Impossible d'extraire le nouveau token dans l'URL retournée.")
new_token = m_new.group(1)
print("New token:", new_token)

# 3) Lire le fichier m3u8 et trouver l'ancien token
text = m3u8_path.read_text(encoding="utf-8")
m_old = re.search(r"https?://[^/]+/([^/]+)/simulcast/", text)
if not m_old:
    sys.exit("Aucun token existant trouvé dans le fichier m3u8.")
old_token = m_old.group(1)
print("Old token:", old_token)

if old_token == new_token:
    print("Le token est déjà à jour.")
    sys.exit(0)

# 4) Sauvegarde et remplacement
backup_path.write_text(text, encoding="utf-8")
updated = text.replace(old_token, new_token)
m3u8_path.write_text(updated, encoding="utf-8")
print(f"Remplacé '{old_token}' par '{new_token}' dans {m3u8_path} (backup: {backup_path}).")
