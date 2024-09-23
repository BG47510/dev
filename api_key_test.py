# -*- coding: utf-8 -*-
"""Module qui construit un fichier xml pour alimenter un EPG."""

import argparse
import datetime
import hashlib
import hmac
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


def workflows_args():
    """Retourne les arguments de la ligne de commande du workflows."""
    parser = argparse.ArgumentParser()
    # Ajoute l'argument pour nos ID externes des canaux.
    parser.add_argument("--int-list", type=str)
    # Ajoute l'argument pour le nombre de jours à télécharger.
    parser.add_argument("--day", type=int, default=2)
    # Analyse et appelle les arguments de la ligne de commande.
    return parser.parse_args()

__ARGS = workflows_args()

def construit_url():
    """Construit l'url (API) de l’application Télérama Programme TV.
    https://play.google.com/store/apps/details?id=com.telerama.fr"""

    # Variables locales liées à la fonction
    api_appareil = "android_tablette"
    date = datetime.date.today()
    id_canal = (
        __ARGS.int_list
    )
    par_page = 3200
    page = 1
    source = "https://api.telerama.fr"
    api_cle = "apitel-5304b49c90511"
    params = f"/v1/programmes/grille?\
appareil={api_appareil}&\
date={date}&\
id_chaines={id_canal}&\
nb_par_page={par_page}&\
page={page}"
    # La méthode translate() avec un dictionnaire remplace "=&?".
    tr_dict = str.maketrans({"=": "", "&": "", "?": ""})
    to_sign = params.translate(tr_dict)
    # Un hachage cryptographique combiné à une clé secrète détermine le niveau de confiance.
    # clé secrète : Eufea9cuweuHeif ou uIF59SZhfrfm5Gb
    hash_cle = "Eufea9cuweuHeif"
    digest_maker = hmac.new(
        b"hash_cle",
        b"to_sign",
        hashlib.sha1,
    )
    digest = digest_maker.hexdigest()
    url = f"{source}\
{params}&\
api_cle={api_cle}&\
api_signature={digest}"
    return url


yu = construit_url()
print(yu)
# *********************************************************************************

# def collecte():
# """Collecte les données."""

api = construit_url() # Déclenche la fonction
with requests.session() as session:
    reponse = session.get(api, headers=__HEADERS)
# retour = session.get(construit_url(), headers=__HEADERS)

# programs = []
# try:
data = reponse.json() # La mise à jour de télérama est à 06h00.
# if reponse.status_code == 200:
# programs += data.get('donnees', [])
# break
# else:
# data = reponse.json()
# if reponse.status_code == 404 and data.get('error') and \
# data.get('msg') == "Il n'y a pas de programmes.":
# break # Aucune données de disponible.
# except ValueError:
# pass

# return programs

print(data)
# *******************************************************************************************

# def tvg_id(args):
# """Convertit l’ID d’une chaîne Télérama en une ID de chaîne XMLTV"""

# channel_id = args.int_list
# return channel_id + ".tv.telerama.fr"

# ty = tvg_id(args)
# print(ty)
# **************************************************************************************************

# channels = ['france2', 'm6', 'w9', 'test_channel_no_present'] #!!!!!!!!!!!!!!!!!!!!!

# telerama_ids = []
# for channel in channels:
# if channel in CHANNELS_ID:
# telerama_ids.append(CHANNELS_ID[channel])

# programme = []
# try:
# data = reponse.json()
# if reponse.status_code == 200:
# programme += data.get('donnees', [])
# break
# else:
# data = reponse.json()
# if reponse.status_code == 404 and data.get('error') and \
# data.get('msg') == "Une erreur est survenue.":
# Plus de page de programme disponible
# break
# except ValueError:
# pass

# return programme
# **********************************************************************************************
# def _parse_program_dict(program):
# def _conversion(program):
# """Extrait, structure et renvoie les données vers un format xmltv."""
# program_dict = {}

# Channel ID
# program_dict['id_chaine'] = program['id_chaine']

# Horaire "horaire":{"debut":"2024-09-13 06:00:00","fin":"2024-09-13 06:30:00"},
# debut = program['horaire']['debut']
# debut_l = debut.split()[1].split(':')
# debut_s = debut_l[0] + 'h' + debut_l[1]
# program_dict['start_time'] = debut_s

# fin = program['horaire']['fin']
# fin_l = fin.split()[1].split(':')
# fin_s = fin_l[0] + 'h' + fin_l[1]
# program_dict['stop_time'] = fin_s

# Titre "titre":"Le 6h info",
# program_dict['title'] = program['titre']

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