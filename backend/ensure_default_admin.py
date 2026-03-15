"""Ensure a default admin account exists in Firebase Auth and Firestore.

Run:
  python ensure_default_admin.py

Optional env overrides:
  DEFAULT_ADMIN_EMAIL
  DEFAULT_ADMIN_PASSWORD
  DEFAULT_ADMIN_NAME
"""

import os
from datetime import datetime, timezone

from firebase_admin import auth as firebase_auth

from firebase_connect import db


DEFAULT_ADMIN_EMAIL = os.getenv("DEFAULT_ADMIN_EMAIL", "CampusCurb30@gmail.com")
DEFAULT_ADMIN_PASSWORD = os.getenv("DEFAULT_ADMIN_PASSWORD", "Campuscurb@2026")
DEFAULT_ADMIN_NAME = os.getenv("DEFAULT_ADMIN_NAME", "CampusCurb Admin")


def ensure_default_admin() -> None:
    email = DEFAULT_ADMIN_EMAIL.strip().lower()
    password = DEFAULT_ADMIN_PASSWORD

    if not email:
        raise ValueError("DEFAULT_ADMIN_EMAIL cannot be empty")
    if len(password) < 6:
        raise ValueError("DEFAULT_ADMIN_PASSWORD must be at least 6 characters")

    try:
        user = firebase_auth.get_user_by_email(email)
        print(f"Auth user exists: {email} ({user.uid})")
    except Exception:
        user = firebase_auth.create_user(email=email, password=password)
        print(f"Created auth user: {email} ({user.uid})")

    db.collection("users").document(user.uid).set(
        {
            "email": email,
            "name": DEFAULT_ADMIN_NAME,
            "role": "admin",
            "department": "",
            "points": 0,
            "isActive": True,
            "createdAt": datetime.now(timezone.utc).isoformat(),
            "seededBy": "ensure_default_admin",
        },
        merge=True,
    )

    print("Admin Firestore profile ensured")
    print("Done")


if __name__ == "__main__":
    ensure_default_admin()