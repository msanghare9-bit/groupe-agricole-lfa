import json, os, requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account
info = json.loads(os.environ["FIREBASE_SA"]); p = info["project_id"]
c = service_account.Credentials.from_service_account_info(info, scopes=["https://www.googleapis.com/auth/cloud-platform","https://www.googleapis.com/auth/firebase"])
c.refresh(Request()); h = {"Authorization": f"Bearer {c.token}"}
cfg = requests.get(f"https://identitytoolkit.googleapis.com/admin/v2/projects/{p}/config", headers=h).json()
print("CONFIG signIn:", json.dumps(cfg.get("signIn"), ensure_ascii=False))
print("CONFIG domaines:", cfg.get("authorizedDomains"))
print("CONFIG autres clés:", [k for k in cfg.keys()])
g = json.load(open("google-services.json")); kand = g["client"][0]["api_key"][0]["current_key"]
apps = requests.get(f"https://firebase.googleapis.com/v1beta1/projects/{p}/webApps", headers=h).json().get("apps", [])
kweb = requests.get(f"https://firebase.googleapis.com/v1beta1/projects/{p}/webApps/{apps[0]['appId']}/config", headers=h).json().get("apiKey") if apps else None
for nom, k, extra in [("android", kand, {}), ("web", kweb, {"Referer": "https://lfarm-1e4fe.web.app/"})]:
    if not k: print(nom, "pas de clé"); continue
    r = requests.post(f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={k}", json={"returnSecureToken": True}, headers=extra)
    print("SIGNUP", nom, k[-6:], r.status_code, r.text[:400])
r = requests.get(f"https://apikeys.googleapis.com/v2/projects/{p}/locations/global/keys", headers=h)
print("KEYS", r.status_code)
for key in r.json().get("keys", []):
    print(" -", key.get("displayName"), json.dumps(key.get("restrictions"), ensure_ascii=False)[:600])
r = requests.get(f"https://serviceusage.googleapis.com/v1/projects/{p}/services?filter=state:ENABLED&pageSize=200", headers=h)
print("SERVICES", r.status_code, sorted(s["config"]["name"] for s in r.json().get("services", [])))
