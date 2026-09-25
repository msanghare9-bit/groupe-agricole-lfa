"""Prépare le projet Android avant la compilation.

Lit google-services.json (à la racine du dépôt), génère lib/firebase_options.dart
et ajuste la configuration Android (version minimale, permission internet, nom).
"""
import json
import pathlib
import re
import sys

RACINE = pathlib.Path(".")
APP = RACINE / "app_build"
PACKAGE = "sn.lfakebemer.groupeagricole"

fichier = RACINE / "google-services.json"
if not fichier.exists():
    sys.exit("ERREUR : google-services.json est introuvable à la racine du dépôt.")

g = json.loads(fichier.read_text(encoding="utf-8"))
projet = g["project_info"]
clients = [c for c in g["client"]
           if c["client_info"]["android_client_info"]["package_name"] == PACKAGE]
if not clients:
    sys.exit(f"ERREUR : aucune application {PACKAGE} dans google-services.json.")
c = clients[0]

options = f"""import 'package:firebase_core/firebase_core.dart';

const firebaseOptions = FirebaseOptions(
  apiKey: '{c["api_key"][0]["current_key"]}',
  appId: '{c["client_info"]["mobilesdk_app_id"]}',
  messagingSenderId: '{projet["project_number"]}',
  projectId: '{projet["project_id"]}',
  storageBucket: '{projet.get("storage_bucket", "")}',
);
"""
(APP / "lib" / "firebase_options.dart").write_text(options, encoding="utf-8")

gradle = APP / "android" / "app" / "build.gradle.kts"
if not gradle.exists():
    gradle = APP / "android" / "app" / "build.gradle"
t = gradle.read_text(encoding="utf-8")
t = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 24", t)
t = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", t)
gradle.write_text(t, encoding="utf-8")

manifeste = APP / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
t = manifeste.read_text(encoding="utf-8")
if "android.permission.INTERNET" not in t:
    t = re.sub(r"(<manifest[^>]*>)",
               r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>',
               t, count=1)
t = t.replace('android:label="groupeagricole"', 'android:label="Groupe Agricole"')
manifeste.write_text(t, encoding="utf-8")

print("Préparation terminée.")
