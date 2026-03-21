import requests
import re
from urllib.parse import urljoin

# Configuration
URL_SOURCE = 'https://hdfauth.ftven.fr/esi/TA?format=json&url=https://simulcast-p.ftven.fr/simulcast/France_2/hls_fr2/index.m3u8'
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
}
NOM_FICHIER = 'fr2.m3u8'

def extraire_url_flux(url_api):
    try:
        response = requests.get(url_api, headers=HEADERS, timeout=10)
        response.raise_for_status()
        return response.json().get('url')
    except Exception as e:
        print(f"❌ Erreur API : {e}")
        return None

def modifier_contenu_m3u8(contenu, base_url):
    lignes = contenu.splitlines()
    nouvelles_lignes = []

    for ligne in lignes:
        ligne = ligne.strip()
        if not ligne:
            continue

        # 1. Si la ligne est un lien direct (ne commence pas par #)
        if not ligne.startswith("#"):
            nouvelles_lignes.append(urljoin(base_url, ligne))
        
        # 2. Si la ligne contient une URI (ex: les clés DRM ou les sous-fichiers)
        elif 'URI="' in ligne:
            # On cherche tout ce qui est entre les guillemets après URI=
            nouvelle_ligne = re.sub(
                r'URI="([^"]+)"', 
                lambda m: f'URI="{urljoin(base_url, m.group(1))}"', 
                ligne
            )
            nouvelles_lignes.append(nouvelle_ligne)
        
        # 3. Sinon, on garde la ligne telle quelle
        else:
            nouvelles_lignes.append(ligne)

    return "\n".join(nouvelles_lignes)

def main():
    print("🚀 Démarrage de l'actualisation...")
    
    m3u_url = extraire_url_flux(URL_SOURCE)
    
    if not m3u_url:
        print("Error: Impossible de récupérer l'URL source.")
        return

    try:
        res = requests.get(m3u_url, headers=HEADERS, timeout=10)
        res.raise_for_status()

        # On définit la base URL pour reconstruire les liens relatifs
        # On prend tout ce qui précède le dernier '/'
        base_url = m3u_url.rsplit('/', 1)[0] + '/'
        
        m3u_modifie = modifier_contenu_m3u8(res.text, base_url)

        with open(NOM_FICHIER, 'w', encoding='utf-8') as f:
            f.write(m3u_modifie)
        
        print(f"✅ Fichier {NOM_FICHIER} mis à jour avec succès.")
        
    except Exception as e:
        print(f"❌ Erreur lors du traitement : {e}")

if __name__ == "__main__":
    main()
