"""Prépare le projet Android avant la compilation.

Lit google-services.json (à la racine du dépôt), génère lib/firebase_options.dart
et ajuste la configuration Android : version minimale, permissions, nom,
et signature permanente (clé fournie par les secrets GitHub).
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

# --- Gradle : version minimale et signature ---
kts = APP / "android" / "app" / "build.gradle.kts"
if kts.exists():
    t = kts.read_text(encoding="utf-8")
    t = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 24", t)
    signature = '''    signingConfigs {
        create("release") {
            storeFile = file("upload.jks")
            storePassword = System.getenv("KS_PASS")
            keyAlias = "groupeagricole"
            keyPassword = System.getenv("KS_PASS")
        }
    }

    buildTypes {'''
    t = t.replace("    buildTypes {", signature, 1)
    t = t.replace('signingConfig = signingConfigs.getByName("debug")',
                  'signingConfig = signingConfigs.getByName("release")')
    t = t.replace("compileOptions {",
                  "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
    t += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    kts.write_text(t, encoding="utf-8")
else:
    groovy = APP / "android" / "app" / "build.gradle"
    t = groovy.read_text(encoding="utf-8")
    t = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", t)
    signature = '''    signingConfigs {
        release {
            storeFile file("upload.jks")
            storePassword System.getenv("KS_PASS")
            keyAlias "groupeagricole"
            keyPassword System.getenv("KS_PASS")
        }
    }

    buildTypes {'''
    t = t.replace("    buildTypes {", signature, 1)
    t = t.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
    t = t.replace("compileOptions {",
                  "compileOptions {\n        coreLibraryDesugaringEnabled true", 1)
    t += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    groovy.write_text(t, encoding="utf-8")

if "signingConfigs.getByName(\"release\")" not in t and "signingConfigs.release" not in t:
    sys.exit("ERREUR : impossible de configurer la signature.")

# --- Manifeste : internet, ouverture des liens, nom ---
manifeste = APP / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
t = manifeste.read_text(encoding="utf-8")
if "android.permission.INTERNET" not in t:
    t = re.sub(r"(<manifest[^>]*>)",
               r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>',
               t, count=1)
lien = '''        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
    </queries>'''
if "</queries>" in t and 'android:scheme="https"' not in t:
    t = t.replace("    </queries>", lien, 1)
permissions = [
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
    "android.permission.VIBRATE",
]
for perm in permissions:
    if perm not in t:
        t = re.sub(r"(<manifest[^>]*>)",
                   r'\1\n    <uses-permission android:name="' + perm + '"/>', t, count=1)
recepteurs = """        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    </application>"""
if "ScheduledNotificationReceiver" not in t:
    t = t.replace("    </application>", recepteurs, 1)
t = t.replace('android:label="groupeagricole"', 'android:label="Groupe Agricole"')
manifeste.write_text(t, encoding="utf-8")

print("Préparation terminée.")

# --- Icône de l'application (logo LFARM) ---
import shutil
icones = RACINE / "assets" / "icone"
res = APP / "android" / "app" / "src" / "main" / "res"
for densite in ["mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"]:
    source = icones / f"ic_launcher_{densite}.png"
    dossier = res / f"mipmap-{densite}"
    if source.exists() and dossier.exists():
        shutil.copy(source, dossier / "ic_launcher.png")
print("Icône installée.")

# --- Installation des mises à jour depuis l'application ---
extra = RACINE / "android_extra"
kotlin = APP / "android" / "app" / "src" / "main" / "kotlin"
cibles = list(kotlin.rglob("MainActivity.kt")) if kotlin.exists() else []
if not cibles:
    sys.exit("ERREUR : MainActivity.kt introuvable.")
shutil.copy(extra / "MainActivity.kt", cibles[0])
xml = APP / "android" / "app" / "src" / "main" / "res" / "xml"
xml.mkdir(parents=True, exist_ok=True)
shutil.copy(extra / "chemins_fichiers.xml", xml / "chemins_fichiers.xml")

t = manifeste.read_text(encoding="utf-8")
if "REQUEST_INSTALL_PACKAGES" not in t:
    t = re.sub(r"(<manifest[^>]*>)",
               r'\1\n    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>',
               t, count=1)
fournisseur = """        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fichiers"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/chemins_fichiers" />
        </provider>
    </application>"""
if "FileProvider" not in t:
    t = t.replace("    </application>", fournisseur, 1)
manifeste.write_text(t, encoding="utf-8")

g = kts if kts.exists() else APP / "android" / "app" / "build.gradle"
t = g.read_text(encoding="utf-8")
if "androidx.core:core" not in t:
    if g.suffix == ".kts":
        t = t.replace('coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")',
                      'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n    implementation("androidx.core:core:1.13.1")')
    else:
        t = t.replace("coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'",
                      "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n    implementation 'androidx.core:core:1.13.1'")
    g.write_text(t, encoding="utf-8")
print("Installateur de mises à jour prêt.")
