"""Publie firestore.rules dans Firebase.

L'adresse du responsable n'est pas écrite dans le dépôt : elle est reprise
des règles actuellement en place et remplace __EMAIL__.
"""
import json
import os
import re
import sys

import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account

info = json.loads(os.environ["FIREBASE_SA"])
cred = service_account.Credentials.from_service_account_info(
    info, scopes=["https://www.googleapis.com/auth/cloud-platform",
                  "https://www.googleapis.com/auth/firebase"])
cred.refresh(Request())
h = {"Authorization": f"Bearer {cred.token}"}
projet = info["project_id"]
base = "https://firebaserules.googleapis.com/v1"
nom_release = f"projects/{projet}/releases/cloud.firestore"

r = requests.get(f"{base}/{nom_release}", headers=h, timeout=30)
r.raise_for_status()
ancien = requests.get(f"{base}/{r.json()['rulesetName']}", headers=h, timeout=30)
ancien.raise_for_status()
source = "".join(f["content"] for f in ancien.json()["source"]["files"])
m = re.search(r'request\.auth\.token\.email\s*==\s*"([^"]+)"', source)
if not m or "VOTRE_EMAIL" in m.group(1) or "__EMAIL__" in m.group(1):
    sys.exit("ERREUR : adresse du responsable introuvable dans les règles actuelles.")
email = m.group(1)

contenu = open("firestore.rules", encoding="utf-8").read().replace("__EMAIL__", email)
nouveau = requests.post(
    f"{base}/projects/{projet}/rulesets", headers=h, timeout=30,
    json={"source": {"files": [{"name": "firestore.rules", "content": contenu}]}})
if nouveau.status_code != 200:
    sys.exit(f"ERREUR règles : {nouveau.status_code} {nouveau.text[:500]}")
maj = requests.patch(
    f"{base}/{nom_release}", headers=h, timeout=30,
    json={"release": {"name": nom_release, "rulesetName": nouveau.json()["name"]}})
if maj.status_code != 200:
    sys.exit(f"ERREUR publication : {maj.status_code} {maj.text[:500]}")
print("Règles publiées.")
