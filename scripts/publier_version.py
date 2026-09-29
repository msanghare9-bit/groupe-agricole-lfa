"""Annonce la nouvelle version à l'application (document config/app)."""
import datetime
import json
import os
import sys

import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account

cle = os.environ.get("FIREBASE_SA")
if not cle:
    sys.exit("ERREUR : clé FIREBASE_SA absente.")
info = json.loads(cle)
cred = service_account.Credentials.from_service_account_info(
    info, scopes=["https://www.googleapis.com/auth/datastore"])
cred.refresh(Request())

numero = int(os.environ["NUMERO"])
depot = os.environ["GITHUB_REPOSITORY"]
lien = f"https://github.com/{depot}/releases/latest/download/LFARM.apk"
maintenant = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

url = (f"https://firestore.googleapis.com/v1/projects/{info['project_id']}"
       "/databases/(default)/documents/config/app")
corps = {"fields": {
    "version": {"integerValue": str(numero)},
    "lien": {"stringValue": lien},
    "date": {"timestampValue": maintenant},
}}
r = requests.patch(url, json=corps, timeout=30,
                   headers={"Authorization": f"Bearer {cred.token}"},
                   params=[("updateMask.fieldPaths", "version"),
                           ("updateMask.fieldPaths", "lien"),
                           ("updateMask.fieldPaths", "date")])
r.raise_for_status()
print(f"Version {numero} annoncée : {lien}")
