"""Prépare la version web : configuration Firebase (application web),
domaines autorisés, options Flutter, icônes et nom de l'application."""
import json, os, pathlib, sys, time
import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account

APP = pathlib.Path("app_web")
info = json.loads(os.environ["FIREBASE_SA"])
projet = info["project_id"]
cred = service_account.Credentials.from_service_account_info(info, scopes=[
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/firebase"])
cred.refresh(Request())
h = {"Authorization": f"Bearer {cred.token}"}
fb = f"https://firebase.googleapis.com/v1beta1/projects/{projet}"

g = json.load(open("google-services.json"))
android = g["client"][0]
conf = {
    "apiKey": android["api_key"][0]["current_key"],
    "appId": android["client_info"]["mobilesdk_app_id"],
    "messagingSenderId": g["project_info"]["project_number"],
    "projectId": projet,
    "authDomain": f"{projet}.firebaseapp.com",
    "storageBucket": g["project_info"].get("storage_bucket", ""),
}
try:
    apps = requests.get(f"{fb}/webApps", headers=h, timeout=30).json().get("apps", [])
    if not apps:
        op = requests.post(f"{fb}/webApps", headers=h, timeout=30,
                           json={"displayName": "LFARM Web"}).json()
        print("Création de l'application web :", str(op)[:200])
        for _ in range(20):
            time.sleep(3)
            apps = requests.get(f"{fb}/webApps", headers=h, timeout=30).json().get("apps", [])
            if apps:
                break
    if apps:
        c = requests.get(f"{fb}/webApps/{apps[0]['appId']}/config", headers=h, timeout=30).json()
        if "appId" in c:
            conf.update({k: c[k] for k in ("apiKey", "appId", "messagingSenderId", "authDomain") if k in c})
            print("Configuration web Firebase obtenue.")
except Exception as e:
    print("Application web Firebase non créée, configuration Android utilisée :", e)

try:
    it = f"https://identitytoolkit.googleapis.com/admin/v2/projects/{projet}/config"
    cfg = requests.get(it, headers=h, timeout=30).json()
    dom = cfg.get("authorizedDomains", [])
    voulus = [f"{projet}.web.app", f"{projet}.firebaseapp.com", "msanghare9-bit.github.io"]
    manque = [d for d in voulus if d not in dom]
    if manque and dom:
        r = requests.patch(it, headers=h, timeout=30, params={"updateMask": "authorizedDomains"},
                           json={"authorizedDomains": dom + manque})
        print("Domaines autorisés :", r.status_code)
except Exception as e:
    print("Domaines non modifiés :", e)

options = "import 'package:firebase_core/firebase_core.dart';\n\nconst firebaseOptions = FirebaseOptions(\n" + "".join(
    f"  {k}: '{conf[k]}',\n" for k in ("apiKey", "appId", "messagingSenderId", "projectId", "authDomain", "storageBucket")) + ");\n"
(APP / "lib" / "firebase_options.dart").write_text(options, encoding="utf-8")

# Icônes et nom
from PIL import Image
ic = Image.open("assets/icone/icone_1024.png").convert("RGB")
web = APP / "web"
for nom, s in [("icons/Icon-192.png", 192), ("icons/Icon-512.png", 512),
               ("icons/Icon-maskable-192.png", 192), ("icons/Icon-maskable-512.png", 512),
               ("favicon.png", 64), ("icons/apple-touch-icon.png", 180)]:
    ic.resize((s, s), Image.LANCZOS).save(web / nom)
m = json.loads((web / "manifest.json").read_text())
m.update({"name": "LFARM", "short_name": "LFARM",
          "description": "Groupe Agricole du LFA Kébémer",
          "background_color": "#FBFAF5", "theme_color": "#2E7D32"})
(web / "manifest.json").write_text(json.dumps(m, indent=2, ensure_ascii=False))
t = (web / "index.html").read_text()
t = t.replace("<title>groupeagricole</title>", "<title>LFARM</title>")
t = t.replace('content="groupeagricole"', 'content="LFARM"')
t = t.replace('href="icons/Icon-192.png">', 'href="icons/apple-touch-icon.png">', 1)
(web / "index.html").write_text(t)
print("Version web préparée.")
