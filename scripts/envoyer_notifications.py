"""Envoie les notifications en attente (collection « notifications »).

Chaque document contient : cible (« groupe » ou « eleve_<nom> »), titre, texte,
envoye (false). Après l'envoi, le document est marqué envoye = true.
"""
import json
import os
import sys

import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account

cle = os.environ.get("FIREBASE_SA")
if not cle:
    print("Pas de clé FIREBASE_SA : rien à envoyer.")
    sys.exit(0)

info = json.loads(cle)
cred = service_account.Credentials.from_service_account_info(
    info,
    scopes=[
        "https://www.googleapis.com/auth/datastore",
        "https://www.googleapis.com/auth/firebase.messaging",
    ],
)
cred.refresh(Request())
entetes = {"Authorization": f"Bearer {cred.token}"}
projet = info["project_id"]
base = f"https://firestore.googleapis.com/v1/projects/{projet}/databases/(default)/documents"

requete = {
    "structuredQuery": {
        "from": [{"collectionId": "notifications"}],
        "where": {
            "fieldFilter": {
                "field": {"fieldPath": "envoye"},
                "op": "EQUAL",
                "value": {"booleanValue": False},
            }
        },
        "limit": 200,
    }
}
r = requests.post(base + ":runQuery", json=requete, headers=entetes, timeout=30)
r.raise_for_status()

traitees = 0
for element in r.json():
    doc = element.get("document")
    if not doc:
        continue
    champs = doc.get("fields", {})

    def texte(k):
        return champs.get(k, {}).get("stringValue", "")

    cible = texte("cible") or "groupe"
    message = {
        "message": {
            "topic": cible,
            "notification": {
                "title": texte("titre") or "Groupe Agricole",
                "body": texte("texte"),
            },
            "android": {"priority": "high"},
        }
    }
    envoi = requests.post(
        f"https://fcm.googleapis.com/v1/projects/{projet}/messages:send",
        json=message, headers=entetes, timeout=30,
    )
    ok = envoi.status_code == 200
    if not ok:
        print("Échec pour", cible, envoi.status_code, envoi.text[:300])
    maj = {
        "fields": {
            "envoye": {"booleanValue": True},
            "resultat": {"stringValue": "ok" if ok else f"erreur {envoi.status_code}"},
        }
    }
    u = requests.patch(
        f"https://firestore.googleapis.com/v1/{doc['name']}",
        params=[("updateMask.fieldPaths", "envoye"), ("updateMask.fieldPaths", "resultat")],
        json=maj, headers=entetes, timeout=30,
    )
    u.raise_for_status()
    traitees += 1

print(f"{traitees} notification(s) traitée(s).")
