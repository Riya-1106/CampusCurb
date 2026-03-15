import json
import os

import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore

# ==========================================
# INITIALIZE FIREBASE CONNECTION
# ==========================================
# On Railway (or any cloud): set FIREBASE_KEY_JSON env var to the full
# contents of firebase_key.json as a single-line JSON string.
# Locally: the file firebase/firebase_key.json is used as a fallback.

_key_json_str = os.environ.get("FIREBASE_KEY_JSON", "").strip()

if _key_json_str:
    cred = credentials.Certificate(json.loads(_key_json_str))
else:
    cred = credentials.Certificate("firebase/firebase_key.json")

if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)

db = firestore.client()

print("Firebase connected successfully")