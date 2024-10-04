# -*- coding: utf-8 -*-
"""Met en œuvre les fonctionnalités de saisie et de traitement nécessaires
à la génération de données XMLTV à partir de l’application Télérama Programme TV."""

#import argparse
import datetime
#import hashlib
#import hmac
import json
import sys

import requests

# ******************************************

CHANNELS_ID = {}  # Construit à la volée

# Variables globales
__SOURCE = "https://api.telerama.fr"
__HEADERS = {"User-agent": "okhttp/3.2.0"}
# __ARGS = workflows_args()
# args = workflows_args()
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

#with requests.session() as session:
    #reponse = session.get(api, headers=__HEADERS)
# retour = session.get(construit_url(), headers=__HEADERS)
reponse = requests.get(api)
programs = []

# Convertie la chaîne JSON en dictionnaire Python.
r_data = reponse.json() # La mise à jour de télérama est à 06h00.
data = r_data['donnees'][0]



...         
program_dict = {}
for prog in data:
    ann = data['annee_realisation']
    program_dict.append(ann)
    #print(ann)
    debut = data['horaire']['debut']
    debut_l = debut.split()[1].split(':')
    debut_s = debut_l[0] + 'h' + debut_l[1]
    h_debut['start_time'] = debut_s
    program_dict.append(h_debut)
#print(debut)
#print(debut_l)
#print(debut_s)
print(program_dict)
#  'horaire': {'debut': '2024-09-13 06:00:00', 'fin': '2024-09-13 06:30:00'}
# start_time_mili = int(data['horaire']['debut']['startTime']['value']) / 1000
titre = data.get('titre')
print(titre)
for slot in reponse.json()['donnees'][0]:
    epg_dict = {}
    title = data.get('titre', '')  
print(epg_dict)
#programs += data.get('donnees', []) # donne une liste
#output = ""
#for key, value in data.items():
    #output += f"{key}: {value}\n"
#print(output)
#sett = dict()
#id = programs.get('id', 0)

# return programs

print(data)
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
# **************************************************************************************************

#channels = ['france2', 'm6', 'w9', 'test_channel_no_present'] #!!!!!!!!!!!!!!!!!!!!!

#telerama_ids = []
#for channel in channels:
    #if channel in CHANNELS_ID:
        #telerama_ids.append(CHANNELS_ID[channel])
        
#print(telerama_ids)

# **********************************************************************************************
# def _parse_program_dict(program):
# def _conversion(program):
# """Extrait, structure et renvoie les données vers un format xmltv."""
#program_dict = {}

# Channel ID
#program_dict['id_chaine'] = programs['id_chaine']
#print(program_dict)
#debut = programs['horaire']['debut']
#debut_l = debut.split()[1].split(':')
#debut_s = debut_l[0] + 'h' + debut_l[1]
#program_dict['start_time'] = debut_s

# fin = program['horaire']['fin']
# fin_l = fin.split()[1].split(':')
# fin_s = fin_l[0] + 'h' + fin_l[1]
# program_dict['stop_time'] = fin_s

# Titre "titre":"Le 6h info",
#program_dict['titre'] = program['titre']

# if program['titre_original']:
# program_dict['originaltitle'] = program['titre_original']

# Sous-titre
# if program['soustitre']:
# program_dict['subtitle'] = program['soustitre']

# Desc
# if program['resume']:
# program_dict['plot'] = utils.strip_tags(
# _fix_xml_unicode_string(program['resume']))

# Catégories
# if program['id_genre']:
# program_dict['genre'] = _TELERAMA_CATEGORIES.get(
# program['id_genre'], 'Inconnue')

# Add specific category
# if program['genre_specifique']:
# program_dict['specific_genre'] = program['genre_specifique']

# Icon
# if 'vignettes' in program:
# program_dict['thumb'] = program['vignettes']['grande']
# program_dict['fanart'] = program['vignettes']['grande169']

# Episode/season
# if program['serie'] and program['serie']['numero_episode']:
# program_dict['season'] = (program['serie'].get('saison', 1) or 1) - 1
# program_dict['episode'] = program['serie']['numero_episode'] - 1

# Video format
# aspect = None
# if program['flags']['est_ar16x9']:
# aspect = '16:9'
# elif program['flags']['est_ar4x3']:
# aspect = '4:3'
# if aspect is not None:
# program_dict['aspect'] = aspect
# if program['flags']['est_hd']:
# program_dict['quality'] = 'HDTV'

# Audio format
# stereo = None
# if program['flags']['est_dolby']:
# stereo = 'dolby'
# elif program['flags']['est_stereoar16x9'] or program['flags']['est_stereo']:
# stereo = 'stereo'
# elif program['flags']['est_vm']:
# stereo = 'bilingual'
# if stereo is not None:
# program_dict['audio'] = stereo

# Vérifie si le programme a déjà été affiché
# if program['flags']['est_premdif'] or program['flags']['est_inedit']:
# program_xml.append(Element('premiere'))
# program_dict['diffusion'] = 'Inédit'
# elif program['flags']['est_redif']:
# program_xml.append(Element('previously-shown'))
# program_dict['diffusion'] = 'Redifusion'
# elif program['flags']['est_derdif']:
# program_xml.append(Element('last-chance'))
# program_dict['diffusion'] = 'Dernière chance'

# Subtitles
# if program['flags']['est_stm']:
# program_xml.append(Element('subtitles', type='deaf-signed'))
# program_dict['subtitles'] = 'deaf-signed'
# elif program['flags']['est_vost']:
# program_xml.append(Element('subtitles', type='onscreen'))
# program_dict['subtitles'] = 'onscreen'

# Star rating
# if program['note_telerama'] > 0:
# program_dict['rating'] = float(program['note_telerama'])

# return program_dict
#print(program_dict)
