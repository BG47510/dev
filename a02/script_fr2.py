import requests
import os
import subprocess
import time

# Configuration
URL_SOURCE = 'https://hdfauth.ftven.fr/esi/TA?format=json&url=https://simulcast-p.ftven.fr/simulcast/France_2/hls_fr2/index.m3u8'
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
}
NOM_FICHIER = 'fr2.m3u8'
OPENVPN_CONFIG = 'vpnbook.ovpn'  # Change ceci avec le chemin de ton fichier .ovpn

def connecter_vpn():
    # Lancer OpenVPN avec le fichier de configuration
    process = subprocess.Popen(['openvpn', '--config', OPENVPN_CONFIG], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    # Donne un peu de temps pour établir la connexion avant d'exécuter le reste du code
    time.sleep(10)  # Ajuste le temps si nécessaire
    return process

def extraire_url_flux(url_api):
    # (Fonction inchangée)
    try:
        response = requests.get(url_api, headers=HEADERS, timeout=10)
        response.raise_for_status()
        return response.json().get('url')
    except Exception as e:
        print(f"Erreur API : {e}")
        return None

def modifier_contenu_m3u8(contenu, base_url):
    # (Fonction inchangée)
    lignes = contenu.splitlines()
    for i in range(len(lignes)):
        if "France_2-avc1" in lignes[i]:
            lignes[i] = base_url + lignes[i]
        elif "URI=" in lignes[i]:
            start = lignes[i].find("URI=") + 5
            end = lignes[i].find("\"", start)
            uri = lignes[i][start:end]
            lignes[i] = lignes[i].replace(uri, base_url + uri)
    return "\n".join(lignes)

def main():
    print("Démarrage de l'actualisation...")
    
    # Connexion au VPN
    vpn_process = connecter_vpn()
    
    try:
        m3u_url = extraire_url_flux(URL_SOURCE)
        
        if not m3u_url:
            print("Impossible de récupérer l'URL source.")
            vpn_process.terminate()
            return

        res = requests.get(m3u_url, headers=HEADERS, timeout=10)
        res.raise_for_status()

        base_url = m3u_url.split('hls_fr2/')[0] + 'hls_fr2/'
        m3u_modifie = modifier_contenu_m3u8(res.text, base_url)

        # Écriture du fichier sur le disque du runner GitHub
        with open(NOM_FICHIER, 'w', encoding='utf-8') as f:
            f.write(m3u_modifie)
        
        print(f"Fichier {NOM_FICHIER} mis à jour avec succès.")
        
    except Exception as e:
        print(f"Erreur lors du traitement du M3U8 : {e}")
    finally:
        # Terminer le processus OpenVPN
        vpn_process.terminate()

if __name__ == "__main__":
    main()

