# -*- coding: utf-8 -*-
"""Met en œuvre les fonctionnalités de saisie et de traitement nécessaires
à la génération de données XMLTV à partir de l’application Télérama Programme TV."""

#import argparse
import datetime
#import hashlib
#import hmac
import json
import sys
import xml.etree.ElementTree as ET


import requests

# ******************************************

CHANNELS_ID = {}  # Construit à la volée
ID_CHAINES = 3
# Variables globales
__SOURCE = "https://api.telerama.fr"
__HEADERS = {"User-agent": "okhttp/3.2.0"}
# __ARGS = workflows_args()
# args = workflows_args()
__DATE = datetime.datetime.now() # la date et l'heure du jour
__JOUR = __DATE.strftime("%Y-%m-%d") # la date du jour
__DEFAULT_DAYS = 1

_API_CLE = "apitel-5304b49c90511"

_API_ENCODING = "UTF-8"
_TELERAMA_PROGRAM_URL = "http://www.telerama.fr"

# _TELERAMA_DATE = '%Y-%m-%d'
# _TELERAMA_TIME = '{} %H:%M:%S'.format(_TELERAMA_DATE_FORMAT)
# _XMLTV_DATETIME = '%Y%m%d%H%M%S %z'
# _XMLTV_DATETIME_PP = '%d/%m/%Y %H:%M:%S'

# _PROGRAM = "tv_grab_fr_teleloisirs"
# **************************************************

# *********************************************************************************

# def collecte():
# """Collecte les données."""

api = "https://github.com/BG47510/dev/raw/refs/heads/main/rama/grille"


j_h = (__JOUR + datetime.timedelta(days=i + offset))

#with requests.session() as session:
    #reponse = session.get(api, headers=__HEADERS)
# retour = session.get(construit_url(), headers=__HEADERS)
reponse = requests.get(api)

# Convertie la chaîne JSON en dictionnaire Python.
r_data = reponse.json() # La mise à jour de télérama est à 06h00.
data1 = r_data.get('donnees', [])
data = r_data['donnees'][0]

days = 1
offset = 0
channels = 3
telerama_programs = []
# L’objet int n’est pas itérable
# Une façon de résoudre le problème est de passer la variable dans la fonction range().
for i in range(0, days):
    #for channel_id in range(channels):
    telerama_programs.append(r_data)
        #construit_url(
        #channel_id,
        #__JOUR + datetime.timedelta(days=i + offset),
        #)
        
print(telerama_programs)
    #france_tz = pytz.timezone("Europe/Paris")
#for programs in telerama_programs:
    #for program in programs:
        #data = [i.strip() for i in program.split("$$$")]



#print(data)
        
print('test***************************************************************************')

contenu = {}
def extrait(r_data):
    contenu['id_chaine'] = [i['id_chaine'] for i in r_data['donnees']]
    contenu['title'] = [i['titre'] for i in r_data['donnees']]
    print(contenu)
    
gaze = extrait(r_data)
print(gaze)
    
print('**********************************************************************************')

program_dict = {}

        # Channel ID
program_dict['id_chaine'] = data['id_chaine']

        # Horaire
debut = data['horaire']['debut']
debut_l = debut.split()[1].split(':')
debut_s = debut_l[0] + 'h' + debut_l[1]
program_dict['start_time'] = debut_s

fin = data['horaire']['fin']
fin_l = fin.split()[1].split(':')
fin_s = fin_l[0] + 'h' + fin_l[1]
program_dict['stop_time'] = fin_s

        # Titre
program_dict['title'] = data['titre']

if data['titre_original']:
    program_dict['originaltitle'] = data['titre_original']

        # Sous-titre
if data['soustitre']:
    program_dict['subtitle'] = data['soustitre']

        # Desc
if data['resume']:
    program_dict['plot'] = data['resume']
    
        # Catégories
#if data['id_genre']:
    #program_dict['genre'] = self._TELERAMA_CATEGORIES.get(data['id_genre'], 'Inconnue')

        # Add specific category
if data['genre_specifique']:
    program_dict['specific_genre'] = data['genre_specifique']

        # Icon
if 'vignettes' in data:
    program_dict['thumb'] = data['vignettes']['grande']
    program_dict['fanart'] = data['vignettes']['grande169']

        # Episode/season
if data['serie'] and program['serie']['numero_episode']:
    program_dict['season'] = (data['serie'].get('saison', 1) or 1) - 1
    program_dict['episode'] = data['serie']['numero_episode'] - 1

        # Video format
aspect = None
if data['flags']['est_ar16x9']:
    aspect = '16:9'
elif data['flags']['est_ar4x3']:
    aspect = '4:3'
if aspect is not None:
    program_dict['aspect'] = aspect
if data['flags']['est_hd']:
    program_dict['quality'] = 'HDTV'

        # Audio format
stereo = None
if data['flags']['est_dolby']:
    stereo = 'dolby'
elif data['flags']['est_stereoar16x9'] or data['flags']['est_stereo']:
    stereo = 'stereo'
elif data['flags']['est_vm']:
    stereo = 'bilingual'
if stereo is not None:
    program_dict['audio'] = stereo

        # Vérifie si le programme a déjà été affiché
if data['flags']['est_premdif'] or data['flags']['est_inedit']:
            # program_xml.append(Element('premiere'))
    program_dict['diffusion'] = 'Inédit'
elif data['flags']['est_redif']:
            # program_xml.append(Element('previously-shown'))
    program_dict['diffusion'] = 'Redifusion'
elif data['flags']['est_derdif']:
            # program_xml.append(Element('last-chance'))
    program_dict['diffusion'] = 'Dernière chance'

        # Subtitles
if data['flags']['est_stm']:
            # program_xml.append(Element('subtitles', type='deaf-signed'))
    program_dict['subtitles'] = 'deaf-signed'
elif data['flags']['est_vost']:
            # program_xml.append(Element('subtitles', type='onscreen'))
    program_dict['subtitles'] = 'onscreen'

        # Star rating
if data['note_telerama'] > 0:
    program_dict['rating'] = float(data['note_telerama'] * 2)  # Pour avoir sur 10 pour Kodi

#print(program_dict, flush=True)
#  'horaire': {'debut': '2024-09-13 06:00:00', 'fin': '2024-09-13 06:30:00'}
# start_time_mili = int(data['horaire']['debut']['startTime']['value']) / 1000

#titre = data.get('titre')

# pour lire et comprendre les données
#tree = ET.parse(data)

#programs += data.get('donnees', []) # donne une liste
#output = ""
#for key, value in data.items():
    #output += f"{key}: {value}\n"
#print(output)
#sett = dict()
#id = programs.get('id', 0)

# return programs

# Vérifie que la variable contient une chaîne Python valide.
# print(type(data)) # > class 'dict'

#print(programs)
#print(id)
# *******************************************************************************************

# def tvg_id(args):
# """Convertit l’ID d’une chaîne Télérama en une ID de chaîne XMLTV"""

# channel_id = args.int_list
# return channel_id + ".tv.telerama.fr"

# ty = tvg_id(args)
# print(ty)
print(' ************************************************************************************************** ')



# **********************************************************************************************

