import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore

# ==========================================
# INITIALIZE FIREBASE CONNECTION
# ==========================================

cred = credentials.Certificate("firebase/firebase_key.json")

if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)

db = firestore.client()

print("Firebase connected successfully")