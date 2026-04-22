from fastapi import FastAPI, HTTPException, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import pandas as pd
import requests
import subprocess
import json
import os
import re
import secrets
import string
import threading
from pathlib import Path
from typing import List, Dict, Optional, Any
from datetime import datetime, timezone


from firebase_admin import auth as firebase_auth
from firebase_admin import firestore as admin_firestore
from firebase_admin import messaging as firebase_messaging
from firebase_connect import db


from log_prediction import apply_operation_actuals
from ml_pipeline import build_demand_dashboard, get_forecast_menu_items, train_models
from predict import (
    demand_dashboard_data,
    generate_forecast,
    get_ml_overview,
    get_rewards,
    menu_optimization,
    predict_demand,
)
from waste_analytics import waste_analysis


app = FastAPI()


app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost",
        "http://127.0.0.1",
        "http://localhost:8000",
        "http://127.0.0.1:8000",
    ],
    allow_origin_regex=(
        r"https?://("
        r"localhost|"
        r"127\.0\.0\.1|"
        r"10(?:\.\d{1,3}){3}|"
        r"192\.168(?:\.\d{1,3}){2}|"
        r"172\.(?:1[6-9]|2\d|3[0-1])(?:\.\d{1,3}){2}"
        r")(?::\d+)?$"
    ),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _extract_bearer_token(authorization: Optional[str]) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid auth token")
    return authorization.split(" ", 1)[1].strip()


_FIRESTORE_READ_TIMEOUT = 3




def _require_authenticated_uid(authorization: Optional[str]) -> str:
    token = _extract_bearer_token(authorization)
    try:
        decoded = firebase_auth.verify_id_token(token)
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid Firebase token") from exc


    uid = decoded.get("uid")
    if not uid:
        raise HTTPException(status_code=401, detail="Invalid token payload")
    return uid




def _require_admin_uid(authorization: Optional[str]) -> str:
    token = _extract_bearer_token(authorization)
    try:
        decoded = firebase_auth.verify_id_token(token)
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid Firebase token") from exc


    uid = decoded.get("uid")
    if not uid:
        raise HTTPException(status_code=401, detail="Invalid token payload")


    user_doc = db.collection("users").document(uid).get(timeout=_FIRESTORE_READ_TIMEOUT)
    if not user_doc.exists:
        raise HTTPException(status_code=403, detail="User profile missing")


    user_data = user_doc.to_dict() or {}
    if user_data.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Admin role required")


    return uid




def _require_role_uid(authorization: Optional[str], allowed_roles: set[str]) -> tuple[str, Dict]:
    uid = _require_authenticated_uid(authorization)
    user_doc = db.collection("users").document(uid).get(timeout=_FIRESTORE_READ_TIMEOUT)
    if not user_doc.exists:
        raise HTTPException(status_code=403, detail="User profile missing")


    user_data = user_doc.to_dict() or {}
    if user_data.get("role") not in allowed_roles:
        raise HTTPException(status_code=403, detail="Insufficient role")
    if user_data.get("isActive") is False:
        raise HTTPException(status_code=403, detail="Account is inactive")


    return uid, user_data



def _resolve_canteen_request(authorization: Optional[str]) -> tuple[str, Dict[str, Any]]:
    try:
        return _require_role_uid(authorization, {"canteen", "admin"})
    except Exception:
        return "canteen", {"role": "canteen"}




def _normalize_domain(value: str) -> str:
    domain = value.strip().lower()
    if domain.startswith("@"):
        domain = domain[1:]
    if "/" in domain:
        domain = domain.split("/", 1)[0]
    return domain




def _email_domain(email: str) -> str:
    normalized = email.strip().lower()
    if "@" not in normalized:
        return ""
    return _normalize_domain(normalized.rsplit("@", 1)[1])




def _normalize_college_key(value: str) -> str:
    cleaned = "".join(ch if ch.isalnum() else "-" for ch in value.strip().lower())
    while "--" in cleaned:
        cleaned = cleaned.replace("--", "-")
    return cleaned.strip("-")


def _safe_int(value: Any, default: int = 0) -> int:
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(round(value))
    try:
        return int(str(value).strip())
    except Exception:
        return default


def _normalize_operation_date(value: Any) -> str:
    raw = str(value or "").strip()
    if not raw:
        return datetime.now().strftime("%Y-%m-%d")
    parsed = pd.to_datetime(raw, errors="coerce")
    if pd.isna(parsed):
        return datetime.now().strftime("%Y-%m-%d")
    return parsed.strftime("%Y-%m-%d")


def _normalized_food_key(value: Any) -> str:
    return "".join(ch if ch.isalnum() else "-" for ch in str(value or "").strip().lower()).strip("-")


def _time_slot_anchor_hour(time_slot: str) -> int:
    normalized = time_slot.strip()
    if normalized == "09:00-11:00":
        return 9
    if normalized == "11:00-13:00":
        return 11
    if normalized == "13:00-15:00":
        return 13
    return 15


def _operation_target_datetime(date_key: str, time_slot: str) -> datetime:
    parsed = pd.to_datetime(date_key, errors="coerce")
    if pd.isna(parsed):
        return datetime.now()
    return datetime(parsed.year, parsed.month, parsed.day, _time_slot_anchor_hour(time_slot))


def _operation_record_id(scope_key: str, date_key: str, time_slot: str, food_item: str) -> str:
    scope = _normalized_food_key(scope_key) or "campus"
    return f"{scope}|{date_key}|{time_slot}|{_normalized_food_key(food_item)}"


def _load_points_cache() -> Dict[str, int]:
    cache = load_data(POINTS_CACHE_FILE, DEFAULT_POINTS_CACHE)
    if isinstance(cache, dict):
        return cache
    return {}


def _baseline_user_points(uid: str) -> int:
    orders = load_data(ORDERS_FILE, DEFAULT_ORDERS)
    order_points = 0
    for order in orders:
        if str(order.get("uid", "")).strip() != uid.strip():
            continue
        quantity = max(_safe_int(order.get("quantity", 1), 1), 1)
        category = str(order.get("category", "")).strip().lower()
        order_points += max(quantity * 10, 10) + _order_bonus_points(category, quantity)

    attendance = load_data(ATTENDANCE_FILE, DEFAULT_ATTENDANCE)
    attendance_points = sum(
        5 for record in attendance if str(record.get("uid", "")).strip() == uid.strip()
    )
    return order_points + attendance_points


def _current_points_from_cache(uid: str) -> int:
    cache = _load_points_cache()
    cached_points = _safe_int(cache.get(uid, 0))
    baseline_points = _baseline_user_points(uid)
    current_points = baseline_points if baseline_points > 0 else cached_points
    if current_points != cached_points:
        cache[uid] = current_points
        save_data(POINTS_CACHE_FILE, cache)
    return current_points


def _set_cached_user_points(uid: str, points: int) -> None:
    cache = _load_points_cache()
    cache[uid] = max(_safe_int(points), 0)
    save_data(POINTS_CACHE_FILE, cache)


def _sync_user_points_to_firestore(uid: str, points: int) -> None:
    try:
        db.collection("users").document(uid).set(
            {
                "points": max(_safe_int(points), 0),
                "updatedAt": datetime.now(timezone.utc).isoformat(),
            },
            merge=True,
            timeout=2,
        )
    except Exception:
        # Firestore sync is best-effort; student actions should stay responsive.
        pass


def _increment_user_points(uid: str, delta: int) -> int:
    current_points = _current_points_from_cache(uid)
    next_points = max(current_points + max(delta, 0), 0)
    _set_cached_user_points(uid, next_points)
    threading.Thread(
        target=_sync_user_points_to_firestore,
        args=(uid, next_points),
        daemon=True,
    ).start()
    return next_points


def _sorted_attendance_records(uid: str) -> List[Dict[str, Any]]:
    attendance = load_data(ATTENDANCE_FILE, DEFAULT_ATTENDANCE)
    records = [
        {
            "id": record.get("id", ""),
            "uid": record.get("uid", ""),
            "date": record.get("date", ""),
            "time": record.get("time", ""),
        }
        for record in attendance
        if str(record.get("uid", "")).strip() == uid.strip()
    ]
    records.sort(
        key=lambda record: f"{record.get('date', '')}T{record.get('time', '')}",
        reverse=True,
    )
    return records


def _attendance_summary(records: List[Dict[str, Any]]) -> Dict[str, Any]:
    today = datetime.now()
    today_key = today.strftime("%Y-%m-%d")
    monthly_count = 0
    streak = 0

    normalized_dates = []
    for record in records:
        raw_date = str(record.get("date", "")).strip()
        try:
            parsed = datetime.fromisoformat(raw_date)
        except Exception:
            continue
        normalized_dates.append(parsed)
        if parsed.year == today.year and parsed.month == today.month:
            monthly_count += 1

    normalized_dates.sort(reverse=True)
    for index, parsed_date in enumerate(normalized_dates):
        expected = today.date().fromordinal(today.date().toordinal() - index)
        if parsed_date.date() == expected:
            streak += 1
        else:
            break

    return {
        "has_marked_today": any(str(record.get("date", "")) == today_key for record in records),
        "current_streak": streak,
        "monthly_attendance": monthly_count,
        "attendance_percentage": round((len(records) / 30) * 100, 2) if records else 0.0,
    }


def _order_bonus_points(category: Optional[str], quantity: int) -> int:
    normalized = str(category or "").strip().lower()
    if quantity <= 0:
        return 0

    if normalized in {"meal", "lunch", "rice"}:
        return quantity * 6
    if normalized in {"breakfast", "snack", "sandwich"}:
        return quantity * 4
    if normalized in {"dessert", "sweet", "beverage", "drinks"}:
        return quantity * 2
    if normalized:
        return quantity * 3
    return 0




def _build_college_key(college_name: str, email: str, domains: List[str]) -> str:
    normalized_domains = [_normalize_domain(d) for d in domains if _normalize_domain(d)]
    if normalized_domains:
        return _normalize_college_key(normalized_domains[0])


    email_domain = _email_domain(email)
    if email_domain:
        return _normalize_college_key(email_domain)


    if college_name.strip():
        return _normalize_college_key(college_name)


    return ""




def _resolve_user_college_key(uid: str, user_data: Dict) -> str:
    raw_key = str(user_data.get("collegeKey", "")).strip()
    if raw_key:
        return _normalize_college_key(raw_key)


    domains = user_data.get("collegeDomains") if isinstance(user_data.get("collegeDomains"), list) else []
    if domains:
        fallback = _normalize_domain(str(domains[0]))
        if fallback:
            return _normalize_college_key(fallback)


    email = str(user_data.get("email", ""))
    email_fallback = _email_domain(email)
    if email_fallback:
        return _normalize_college_key(email_fallback)


    name_fallback = str(user_data.get("collegeName", "") or user_data.get("name", ""))
    if name_fallback.strip():
        return _normalize_college_key(name_fallback)


    return uid




def _validate_strong_password(password: str) -> Optional[str]:
    if not password:
        return "Password is required"
    if len(password) < 8:
        return "Password must be at least 8 characters"
    if re.search(r"\s", password):
        return "Password cannot contain spaces"
    if not re.search(r"[A-Z]", password):
        return "Password must contain at least one uppercase letter"
    if not re.search(r"[a-z]", password):
        return "Password must contain at least one lowercase letter"
    if not re.search(r"\d", password):
        return "Password must contain at least one number"
    if not re.search(r"[^A-Za-z0-9]", password):
        return "Password must contain at least one special character"
    return None




def _generate_strong_password(length: int = 20) -> str:
    alphabet = string.ascii_letters + string.digits + "@#$%&*?!"
    while True:
        password = "".join(secrets.choice(alphabet) for _ in range(length))
        if _validate_strong_password(password) is None:
            return password




def _send_password_setup_email(email: str, college_name: str, reset_link: str) -> None:
    brevo_api_key = os.getenv("BREVO_API_KEY", "").strip()
    from_email = os.getenv("SMTP_FROM_EMAIL", "noreply@campuscurb.com").strip()
    from_name = os.getenv("SMTP_FROM_NAME", "CampusCurb").strip() or "CampusCurb"

    if not brevo_api_key:
        raise HTTPException(
            status_code=500,
            detail="BREVO_API_KEY is not configured.",
        )

    display_name = college_name.strip() or "College Partner"
    payload = {
        "sender": {"name": from_name, "email": from_email},
        "to": [{"email": email, "name": display_name}],
        "subject": "Set your CampusCurb college account password",
        "textContent": (
            f"Hello {display_name},\n\n"
            "Your college access request has been approved.\n"
            "Use the secure link below to set your password:\n\n"
            f"{reset_link}\n\n"
            "This link is single-use and may expire. If it expires, use the Forgot Password option in the app.\n\n"
            "Regards,\n"
            "CampusCurb Team"
        ),
    }

    try:
        response = requests.post(
            "https://api.brevo.com/v3/smtp/email",
            headers={
                "accept": "application/json",
                "api-key": brevo_api_key,
                "content-type": "application/json",
            },
            json=payload,
            timeout=20,
        )
        if response.status_code >= 400:
            raise HTTPException(
                status_code=500,
                detail=(
                    "Failed to send password setup email: "
                    f"Brevo returned {response.status_code}. Response: {response.text}"
                ),
            )
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to send password setup email: {str(exc)}",
        ) from exc


def _send_college_rejection_email(email: str, college_name: str, rejection_note: str) -> None:
    brevo_api_key = os.getenv("BREVO_API_KEY", "").strip()
    from_email = os.getenv("SMTP_FROM_EMAIL", "noreply@campuscurb.com").strip()
    from_name = os.getenv("SMTP_FROM_NAME", "CampusCurb").strip() or "CampusCurb"

    if not brevo_api_key:
        raise HTTPException(
            status_code=500,
            detail="BREVO_API_KEY is not configured.",
        )

    display_name = college_name.strip() or "College Partner"
    note_section = f"\n\nReason for rejection:\n{rejection_note.strip()}" if rejection_note.strip() else ""
    payload = {
        "sender": {"name": from_name, "email": from_email},
        "to": [{"email": email, "name": display_name}],
        "subject": "CampusCurb College Signup Application Status",
        "textContent": (
            f"Hello {display_name},\n\n"
            "Your college access request for CampusCurb has been reviewed and unfortunately rejected.\n"
            f"{note_section}\n\n"
            "If you believe this is an error or would like to reapply, please contact our support team.\n\n"
            "Regards,\n"
            "CampusCurb Team"
        ),
    }

    try:
        response = requests.post(
            "https://api.brevo.com/v3/smtp/email",
            headers={
                "accept": "application/json",
                "api-key": brevo_api_key,
                "content-type": "application/json",
            },
            json=payload,
            timeout=20,
        )
        if response.status_code >= 400:
            raise HTTPException(
                status_code=500,
                detail=(
                    "Failed to send rejection email: "
                    f"Brevo returned {response.status_code}. Response: {response.text}"
                ),
            )
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to send rejection email: {str(exc)}",
        ) from exc


# ==========================================
# INPUT MODEL FOR PREDICTION
# ==========================================


class PredictionInput(BaseModel):


    food_item: str
    time_slot: str = "11:00-13:00"
    weather_type: str = "Sunny"
    price: int = 80
    temperature: int = 30
    food_category: Optional[str] = None
    is_veg: Optional[int] = None
    is_holiday: int = 0
    is_exam_day: int = 0




# ==========================================
# HOME ROUTE
# ==========================================


@app.get("/")
def home():
    return {"message": "Food Demand Prediction API Running"}




# ==========================================
# PREDICT DEMAND
# ==========================================


@app.post("/predict")
def predict(data: PredictionInput):


    input_data = {


        "food_item": data.food_item,
        "time_slot": data.time_slot,
        "weather_type": data.weather_type,
        "price": data.price,
        "temperature": data.temperature,
        "food_category": data.food_category,
        "is_veg": data.is_veg,
        "is_holiday": data.is_holiday,
        "is_exam_day": data.is_exam_day,


    }


    prediction = predict_demand(input_data)


    return {
        "food_item": prediction["food_item"],
        "predicted_demand": prediction["predicted_demand"],
        "suggested_preparation": prediction["suggested_preparation"],
        "expected_waste": prediction.get("expected_waste", 0),
        "recent_average_sales": prediction.get("recent_average_sales", 0),
        "historical_average_sales": prediction.get("historical_average_sales", 0),
        "confidence_score": prediction.get("confidence_score", 0),
        "confidence_label": prediction.get("confidence_label", "Low"),
        "trend_direction": prediction.get("trend_direction", "stable"),
        "trend_reason": prediction.get("trend_reason", ""),
        "recommended_action": prediction.get("recommended_action", ""),
        "feature_snapshot": prediction.get("feature_snapshot", {}),
        "model_name": prediction.get("model_name", "Unknown"),
        "target_date": prediction.get("target_date"),
        "time_slot": prediction.get("time_slot"),
    }




# ==========================================
# MENU OPTIMIZATION
# ==========================================


@app.get("/menu-optimization")
def menu_analysis():
    return menu_optimization()


# ==========================================
# STUDENT ANALYTICS
# ==========================================


@app.get("/student-analytics")
def analytics():


    from student_analytics import student_behavior


    return student_behavior()




@app.get("/prediction-accuracy")
def prediction_accuracy():


    from student_analytics import prediction_accuracy_summary


    return prediction_accuracy_summary()


# ==========================================
# GET REWARDS
# ==========================================


@app.get("/rewards/{points}")
def get_user_rewards(points: int):


    reward = get_rewards(points)


    return {"points": points, "reward": reward}




# ==========================================
# GET DAILY FORECAST
# ==========================================


@app.get("/forecast")
def forecast():
    return generate_forecast()


@app.get("/waste-analytics")
def waste():


    return waste_analysis()




@app.get("/waste-report")
def waste_report():


    report = waste_analysis()
    if "error" in report:
        return report


    return {
        "Total Prepared": report.get("total_food_prepared", 0),
        "Total Sold": report.get("total_food_sold", 0),
        "Total Wasted": report.get("total_food_wasted", 0),
        "Waste Percentage": f"{int(round(report.get('waste_percentage', 0)))}%",
        "Estimated ML Waste Reduction": int(round(report.get("estimated_reduction", 0))),
        "Resolved ML Predictions": int(report.get("prediction_count_used", 0)),
        "Waste Baseline": int(report.get("baseline_waste", report.get("total_food_wasted", 0))),
        "Note": report.get("note", ""),
    }




# ==========================================
# WASTE ANALYTICS (Flutter compatible)
# ==========================================


@app.get("/waste_analytics")
def waste_analytics():


    return waste_analysis()




# ==========================================
# DEMAND FORECAST DASHBOARD
# ==========================================


@app.get("/demand-dashboard")
def demand_dashboard():
    return demand_dashboard_data()


@app.get("/ml/overview")
def ml_overview():
    return get_ml_overview()




# ==========================================
# ADMIN WORKFLOW STORAGE + ENDPOINTS
# ==========================================


DATA_DIR = Path("./data")
DATA_DIR.mkdir(exist_ok=True)
MENU_FILE = DATA_DIR / "admin_menu_pending.json"
EXCHANGE_FILE = DATA_DIR / "admin_exchange_requests.json"


MENU_MASTER = DATA_DIR / "menu.json"
ORDERS_FILE = DATA_DIR / "orders.json"
ATTENDANCE_FILE = DATA_DIR / "attendance.json"
OPERATIONS_FILE = DATA_DIR / "canteen_operations.json"
POINTS_CACHE_FILE = DATA_DIR / "user_points_cache.json"


DEFAULT_MENU_PENDING = [
    {
        "id": "m1",
        "name": "Veg Wrap",
        "price": 80,
        "category": "sandwich",
        "requestedBy": "canteen123",
        "createdAt": "2026-03-14T08:00:00Z"
    },
    {
        "id": "m2",
        "name": "Masala Dosa",
        "price": 50,
        "category": "breakfast",
        "requestedBy": "canteen123",
        "createdAt": "2026-03-14T08:20:00Z"
    }
]


DEFAULT_EXCHANGE_REQUESTS = [
    {
        "id": "e1",
        "title": "Exchange Veg Biryani for Paneer Rice",
        "requestedBy": "student001",
        "status": "pending",
        "createdAt": "2026-03-14T09:00:00Z"
    },
    {
        "id": "e2",
        "title": "Exchange French Fries for Salad",
        "requestedBy": "student002",
        "status": "pending",
        "createdAt": "2026-03-14T09:10:00Z"
    }
]


DEFAULT_MENU = [
    {"id": "1", "name": "Veg Wrap", "price": 80},
    {"id": "2", "name": "Masala Dosa", "price": 50},
    {"id": "3", "name": "Cheese Pizza", "price": 120},
]


DEFAULT_ORDERS = []
DEFAULT_ATTENDANCE = []
DEFAULT_OPERATIONS = []
DEFAULT_POINTS_CACHE = {}
LOGIN_ATTEMPTS_FILE = DATA_DIR / "auth_login_attempts.json"
DEFAULT_LOGIN_ATTEMPTS = []




def load_data(path: Path, default):
    if not path.exists():
        path.write_text(json.dumps(default, indent=2))
    try:
        return json.loads(path.read_text())
    except Exception:
        path.write_text(json.dumps(default, indent=2))
        return default




def save_data(path: Path, payload):
    path.write_text(json.dumps(payload, indent=2))


def _sync_operation_to_firestore(operation: Dict[str, Any]) -> None:
    try:
        db.collection("canteen_operations").document(str(operation.get("id", ""))).set(operation, merge=True)
    except Exception:
        pass


def _resolve_operation_logs_async(operations: List[Dict[str, Any]]) -> None:
    try:
        for operation in operations:
            apply_operation_actuals(
                food_item=str(operation.get("food_item", "")),
                target_date=str(operation.get("date", "")),
                time_slot=str(operation.get("time_slot", "")),
                actual_prepared=_safe_int(operation.get("quantity_prepared")),
                actual_sold=_safe_int(operation.get("quantity_sold")),
                actual_wasted=_safe_int(operation.get("quantity_wasted")),
            )
    except Exception:
        pass


def _operations_for_scope(
    *,
    date_key: str,
    time_slot: str,
    college_key: str,
    uid: str,
) -> List[Dict[str, Any]]:
    operations = load_data(OPERATIONS_FILE, DEFAULT_OPERATIONS)
    rows = []
    for row in operations:
        if not isinstance(row, dict):
            continue
        if str(row.get("date", "")).strip() != date_key:
            continue
        if str(row.get("time_slot", "")).strip() != time_slot:
            continue
        row_college_key = str(row.get("college_key", "")).strip()
        if college_key and row_college_key and row_college_key != college_key:
            continue
        if not college_key and str(row.get("recorded_by", "")).strip() not in {"", uid}:
            continue
        rows.append(dict(row))
    return rows


def _operations_summary(rows: List[Dict[str, Any]]) -> Dict[str, int]:
    return {
        "records_with_inputs": sum(
            1
            for row in rows
            if _safe_int(row.get("quantity_prepared")) > 0
            or _safe_int(row.get("quantity_sold")) > 0
            or _safe_int(row.get("quantity_wasted")) > 0
            or str(row.get("notes", "")).strip() != ""
        ),
        "total_prepared": sum(_safe_int(row.get("quantity_prepared")) for row in rows),
        "total_sold": sum(_safe_int(row.get("quantity_sold")) for row in rows),
        "total_wasted": sum(_safe_int(row.get("quantity_wasted")) for row in rows),
    }


def _operations_view_rows(
    *,
    date_key: str,
    time_slot: str,
    college_key: str = "",
    uid: str = "",
    restrict_to_user: bool = False,
) -> List[Dict[str, Any]]:
    if restrict_to_user:
        scoped_rows = _operations_for_scope(
            date_key=date_key,
            time_slot=time_slot,
            college_key=college_key,
            uid=uid,
        )
    else:
        operations = load_data(OPERATIONS_FILE, DEFAULT_OPERATIONS)
        scoped_rows = [
            dict(row)
            for row in operations
            if isinstance(row, dict)
            and str(row.get("date", "")).strip() == date_key
            and str(row.get("time_slot", "")).strip() == time_slot
        ]
    rows_by_food = {
        _normalized_food_key(row.get("food_item")): dict(row) for row in scoped_rows
    }

    merged_items: List[Dict[str, Any]] = []
    for menu_item in get_forecast_menu_items():
        food_item = str(menu_item.get("name", "")).strip()
        if not food_item:
            continue
        existing = rows_by_food.pop(_normalized_food_key(food_item), None)
        if existing is not None:
            merged_items.append(
                {
                    "food_item": existing.get("food_item", food_item),
                    "food_category": existing.get(
                        "food_category", menu_item.get("category", "general")
                    ),
                    "predicted_demand": _safe_int(existing.get("predicted_demand")),
                    "suggested_preparation": _safe_int(existing.get("suggested_preparation")),
                    "expected_waste": _safe_int(existing.get("quantity_wasted")),
                    "recent_average_sales": _safe_int(existing.get("recent_average_sales")),
                    "historical_average_sales": _safe_int(existing.get("historical_average_sales")),
                    "historical_preparation_average": _safe_int(
                        existing.get("historical_preparation_average")
                    ),
                    "historical_waste_average": _safe_int(existing.get("historical_waste_average")),
                    "confidence_score": existing.get("confidence_score", 0),
                    "confidence_label": existing.get("confidence_label", "Low"),
                    "trend_direction": existing.get("trend_direction", "stable"),
                    "trend_reason": existing.get(
                        "trend_reason", "Saved canteen record for this slot."
                    ),
                    "recommended_action": existing.get(
                        "recommended_action", "Review manually."
                    ),
                    "time_slot": existing.get("time_slot", time_slot),
                    "target_date": existing.get("date", date_key),
                    "weather_type": existing.get("weather_type", "Sunny"),
                    "temperature": _safe_int(existing.get("temperature"), 29),
                    "model_name": existing.get("model_name", "Saved Record"),
                    "feature_snapshot": existing.get("feature_snapshot", {}),
                    "quantity_prepared": _safe_int(existing.get("quantity_prepared")),
                    "quantity_sold": _safe_int(existing.get("quantity_sold")),
                    "quantity_wasted": _safe_int(existing.get("quantity_wasted")),
                    "notes": str(existing.get("notes", "")),
                    "price": _safe_int(existing.get("price"), _safe_int(menu_item.get("price"))),
                }
            )
            continue

        merged_items.append(
            {
                "food_item": food_item,
                "food_category": str(menu_item.get("category", "general")).strip().lower() or "general",
                "predicted_demand": 0,
                "suggested_preparation": 0,
                "expected_waste": 0,
                "recent_average_sales": 0,
                "historical_average_sales": 0,
                "historical_preparation_average": 0,
                "historical_waste_average": 0,
                "confidence_score": 0,
                "confidence_label": "Low",
                "trend_direction": "stable",
                "trend_reason": "No saved operations yet.",
                "recommended_action": "Enter today's operations.",
                "time_slot": time_slot,
                "target_date": date_key,
                "weather_type": "Sunny",
                "temperature": 29,
                "model_name": "Saved Record",
                "feature_snapshot": {},
                "quantity_prepared": 0,
                "quantity_sold": 0,
                "quantity_wasted": 0,
                "notes": "",
                "price": _safe_int(menu_item.get("price")),
            }
        )

    for existing in rows_by_food.values():
        merged_items.append(
            {
                "food_item": existing.get("food_item", ""),
                "food_category": existing.get("food_category", "general"),
                "predicted_demand": _safe_int(existing.get("predicted_demand")),
                "suggested_preparation": _safe_int(existing.get("suggested_preparation")),
                "expected_waste": _safe_int(existing.get("quantity_wasted")),
                "recent_average_sales": _safe_int(existing.get("recent_average_sales")),
                "historical_average_sales": _safe_int(existing.get("historical_average_sales")),
                "historical_preparation_average": _safe_int(existing.get("historical_preparation_average")),
                "historical_waste_average": _safe_int(existing.get("historical_waste_average")),
                "confidence_score": existing.get("confidence_score", 0),
                "confidence_label": existing.get("confidence_label", "Low"),
                "trend_direction": existing.get("trend_direction", "stable"),
                "trend_reason": existing.get(
                    "trend_reason", "Saved canteen record outside the menu list."
                ),
                "recommended_action": existing.get("recommended_action", "Review manually."),
                "time_slot": existing.get("time_slot", time_slot),
                "target_date": existing.get("date", date_key),
                "weather_type": existing.get("weather_type", "Sunny"),
                "temperature": _safe_int(existing.get("temperature"), 29),
                "model_name": existing.get("model_name", "Saved Record"),
                "feature_snapshot": existing.get("feature_snapshot", {}),
                "quantity_prepared": _safe_int(existing.get("quantity_prepared")),
                "quantity_sold": _safe_int(existing.get("quantity_sold")),
                "quantity_wasted": _safe_int(existing.get("quantity_wasted")),
                "notes": str(existing.get("notes", "")),
                "price": _safe_int(existing.get("price")),
            }
        )

    return merged_items




class LoginAttemptInput(BaseModel):
    email: str
    method: str
    success: bool
    reason: str = ""
    selected_role: str = ""




@app.post("/auth/login-attempt")
def log_login_attempt(payload: LoginAttemptInput, request: Request):
    attempts = load_data(LOGIN_ATTEMPTS_FILE, DEFAULT_LOGIN_ATTEMPTS)
    attempts.append({
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "email": payload.email.strip().lower(),
        "method": payload.method,
        "success": payload.success,
        "reason": payload.reason,
        "selected_role": payload.selected_role,
        "ip": request.client.host if request.client else "unknown",
        "user_agent": request.headers.get("user-agent", "unknown"),
    })
    # Keep latest 1000 events
    if len(attempts) > 1000:
        attempts = attempts[-1000:]
    save_data(LOGIN_ATTEMPTS_FILE, attempts)
    return {"message": "Login attempt logged"}




@app.get("/admin/login-attempts")
def admin_login_attempts(authorization: Optional[str] = Header(default=None)):
    _require_admin_uid(authorization)
    attempts = load_data(LOGIN_ATTEMPTS_FILE, DEFAULT_LOGIN_ATTEMPTS)
    return list(reversed(attempts))




class AdminCreateUserInput(BaseModel):
    email: str
    password: str
    role: str
    name: str = ""
    department: str = ""
    college_name: str = ""
    college_domains: List[str] = []




@app.post("/admin/create-user")
def admin_create_user(
    payload: AdminCreateUserInput,
    authorization: Optional[str] = Header(default=None),
):
    admin_uid = _require_admin_uid(authorization)


    role = payload.role.strip().lower()
    allowed_roles = {"student", "faculty", "canteen", "college", "admin"}
    if role not in allowed_roles:
        raise HTTPException(status_code=400, detail="Invalid role")


    email = payload.email.strip().lower()
    if not email:
        raise HTTPException(status_code=400, detail="Email is required")
    password_error = _validate_strong_password(payload.password)
    if password_error:
        raise HTTPException(status_code=400, detail=password_error)


    try:
        created_user = firebase_auth.create_user(email=email, password=payload.password)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Unable to create user: {str(exc)}") from exc


    normalized_domains = []
    for domain in payload.college_domains:
        parsed = _normalize_domain(str(domain))
        if parsed and parsed not in normalized_domains:
            normalized_domains.append(parsed)


    email_domain = _email_domain(email)
    if role == "college" and email_domain and email_domain not in normalized_domains:
        normalized_domains.append(email_domain)


    college_name = payload.college_name.strip()
    if role == "college" and not college_name:
        college_name = payload.name.strip() or (email_domain or "College")


    college_key = ""
    if role in {"college", "student", "faculty", "canteen"}:
        college_key = _build_college_key(college_name, email, normalized_domains)


    user_doc = {
        "name": payload.name.strip(),
        "email": email,
        "role": role,
        "department": payload.department.strip(),
        "points": 0,
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "createdBy": admin_uid,
        "isActive": True,
    }


    if college_name:
        user_doc["collegeName"] = college_name
    if normalized_domains:
        user_doc["collegeDomains"] = normalized_domains
    if college_key:
        user_doc["collegeKey"] = college_key


    db.collection("users").document(created_user.uid).set(user_doc, merge=True)


    return {
        "message": "User created",
        "uid": created_user.uid,
        "email": email,
        "role": role,
    }




@app.get("/admin/menu-pending")
def admin_menu_pending():
    docs = db.collection("menu_pending").where("status", "==", "pending").stream()
    pending_items = []
    for doc in docs:
        data = doc.to_dict() or {}
        pending_items.append({
            "id": doc.id,
            "item_id": doc.id,
            "name": data.get("name", ""),
            "price": data.get("price", 0),
            "category": data.get("category", "general"),
            "status": data.get("status", "pending"),
            "approved": data.get("approved", False),
            "createdAt": data.get("createdAt"),
        })
    return pending_items




class MenuAction(BaseModel):
    id: str




@app.post("/admin/menu-approve")
def admin_menu_approve(payload: MenuAction):
    pending_ref = db.collection("menu_pending").document(payload.id)
    pending_doc = pending_ref.get()
    if not pending_doc.exists:
        raise HTTPException(status_code=404, detail="Menu item not found")


    pending_data = pending_doc.to_dict() or {}


    db.collection("menu").document(payload.id).set({
        "name": pending_data.get("name", ""),
        "price": pending_data.get("price", 0),
        "category": pending_data.get("category", "general"),
        "approved": True,
        "status": "approved",
        "approvedAt": datetime.now(timezone.utc).isoformat(),
    }, merge=True)


    # Move flow: remove from pending after approval.
    pending_ref.delete()
    return {"message": "Menu item approved", "id": payload.id}




@app.post("/admin/menu-reject")
def admin_menu_reject(payload: MenuAction):
    pending_ref = db.collection("menu_pending").document(payload.id)
    pending_doc = pending_ref.get()
    if not pending_doc.exists:
        raise HTTPException(status_code=404, detail="Menu item not found")


    pending_ref.set({
        "status": "rejected",
        "rejectedAt": datetime.now(timezone.utc).isoformat(),
    }, merge=True)


    return {"message": "Menu item rejected", "id": payload.id}




class ExchangeStatus(BaseModel):
    id: str
    status: str
    rejection_note: Optional[str] = None




class CollegeSignupRequestInput(BaseModel):
    college_name: str
    contact_name: str
    email: str
    phone: str = ""
    notes: str = ""
    allowed_domains: List[str] = []




class CollegeFoodListingInput(BaseModel):
    food_item: str
    quantity: int
    unit: str = "plates"
    pickup_window: str = ""
    notes: str = ""




class CollegeFoodRequestInput(BaseModel):
    listing_id: str
    quantity: int
    notes: str = ""




def _user_display_name(user_data: Dict) -> str:
    return (
        user_data.get("collegeName")
        or user_data.get("name")
        or user_data.get("department")
        or user_data.get("email")
        or "Unknown"
    )




def _serialize_docs(docs) -> List[Dict]:
    rows = []
    for doc in docs:
        rows.append({"id": doc.id, **(doc.to_dict() or {})})
    return rows




@app.post("/college/signup-request")
def create_college_signup_request(payload: CollegeSignupRequestInput):
    email = payload.email.strip().lower()
    if not payload.college_name.strip():
        raise HTTPException(status_code=400, detail="College name is required")
    if not payload.contact_name.strip():
        raise HTTPException(status_code=400, detail="Contact name is required")
    if not email:
        raise HTTPException(status_code=400, detail="Email is required")


    requested_domains = []
    for domain in payload.allowed_domains:
        parsed = _normalize_domain(str(domain))
        if parsed and parsed not in requested_domains:
            requested_domains.append(parsed)


    email_domain = _email_domain(email)
    if email_domain and email_domain not in requested_domains:
        requested_domains.append(email_domain)


    college_key = _build_college_key(payload.college_name, email, requested_domains)


    existing = list(
        db.collection("college_signup_requests")
        .where("email", "==", email)
        .where("status", "==", "pending")
        .limit(1)
        .stream()
    )
    if existing:
        raise HTTPException(status_code=400, detail="A signup request is already pending for this email")


    doc_ref = db.collection("college_signup_requests").document()
    doc_ref.set({
        "college_name": payload.college_name.strip(),
        "contact_name": payload.contact_name.strip(),
        "email": email,
        "allowed_domains": requested_domains,
        "primary_domain": requested_domains[0] if requested_domains else "",
        "college_key": college_key,
        "phone": payload.phone.strip(),
        "notes": payload.notes.strip(),
        "status": "pending",
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }, merge=True)
    return {"message": "College signup request submitted", "id": doc_ref.id}




@app.get("/admin/exchange-requests")
def admin_exchange_requests(authorization: Optional[str] = Header(default=None)):
    _require_admin_uid(authorization)
    return {
        "signup_requests": _serialize_docs(
            db.collection("college_signup_requests").order_by("createdAt", direction="DESCENDING").stream()
        ),
        "pending_listings": _serialize_docs(
            db.collection("college_food_listings").order_by("createdAt", direction="DESCENDING").stream()
        ),
        "food_requests": _serialize_docs(
            db.collection("college_food_requests").order_by("createdAt", direction="DESCENDING").stream()
        ),
    }




@app.post("/admin/exchange-status")
def admin_exchange_status(
    payload: ExchangeStatus,
    authorization: Optional[str] = Header(default=None),
):
    admin_uid = _require_admin_uid(authorization)
    valid = {"approved", "rejected", "pending"}
    if payload.status not in valid:
        raise HTTPException(status_code=400, detail="Invalid status")


    signup_ref = db.collection("college_signup_requests").document(payload.id)
    signup_doc = signup_ref.get()
    if signup_doc.exists:
        signup_data = signup_doc.to_dict() or {}
        email = str(signup_data.get("email", "")).strip().lower()


        if payload.status == "approved":
            if not email:
                raise HTTPException(status_code=400, detail="Signup request is missing email")


            college_name = str(signup_data.get("college_name", "")).strip()
            allowed_domains = signup_data.get("allowed_domains")
            normalized_domains = []
            if isinstance(allowed_domains, list):
                for domain in allowed_domains:
                    parsed = _normalize_domain(str(domain))
                    if parsed and parsed not in normalized_domains:
                        normalized_domains.append(parsed)
            email_domain = _email_domain(email)
            if email_domain and email_domain not in normalized_domains:
                normalized_domains.append(email_domain)


            college_key = _build_college_key(college_name, email, normalized_domains)
            if not college_key:
                college_key = _normalize_college_key(email_domain or "college")


            created_new_auth_user = False
            auth_user = None


            try:
                auth_user = firebase_auth.get_user_by_email(email)
            except Exception:
                try:
                    auth_user = firebase_auth.create_user(
                        email=email,
                        password=_generate_strong_password(),
                    )
                    created_new_auth_user = True
                except Exception as exc:
                    raise HTTPException(
                        status_code=400,
                        detail=f"Unable to provision college auth account: {str(exc)}",
                    ) from exc


            reset_link = ""
            password_setup_email_sent = False
            password_setup_email_error = ""

            try:
                reset_link = firebase_auth.generate_password_reset_link(email)
            except Exception as exc:
                if created_new_auth_user and auth_user is not None:
                    try:
                        firebase_auth.delete_user(auth_user.uid)
                    except Exception:
                        pass
                raise HTTPException(
                    status_code=500,
                    detail=f"Unable to create password setup link: {str(exc)}",
                ) from exc

            try:
                _send_password_setup_email(email, college_name, reset_link)
                password_setup_email_sent = True
            except HTTPException as exc:
                password_setup_email_error = str(exc.detail)
                print(f"Warning: Could not send approval email to {email}: {password_setup_email_error}")
            except Exception as exc:
                password_setup_email_error = str(exc)
                print(f"Warning: Could not send approval email to {email}: {password_setup_email_error}")


            db.collection("users").document(auth_user.uid).set(
                {
                    "name": signup_data.get("contact_name", "") or college_name,
                    "email": email,
                    "role": "college",
                    "department": "",
                    "collegeName": college_name,
                    "collegeDomains": normalized_domains,
                    "collegeKey": college_key,
                    "points": 0,
                    "createdAt": datetime.now(timezone.utc).isoformat(),
                    "createdBy": admin_uid,
                    "isActive": True,
                    "provisionedFromSignupRequestId": payload.id,
                },
                merge=True,
            )


        signup_ref.set({
            "status": payload.status,
            "reviewedAt": datetime.now(timezone.utc).isoformat(),
            "reviewedBy": admin_uid,
            "rejectionNote": payload.rejection_note or "",
        }, merge=True)
        
        # Send rejection email if status is rejected
        if payload.status == "rejected" and email:
            college_name = str(signup_data.get("college_name", "")).strip()
            rejection_note = payload.rejection_note or "No reason provided."
            try:
                _send_college_rejection_email(email, college_name, rejection_note)
            except Exception as exc:
                # Log but don't fail the request if email fails
                print(f"Warning: Failed to send rejection email to {email}: {str(exc)}")
        
        response = {"message": "Signup request updated", "id": payload.id, "status": payload.status}
        if payload.status == "approved":
            response["provisioned_email"] = email
            response["auth_user_created"] = created_new_auth_user
            response["password_setup_email_sent"] = password_setup_email_sent
            response["password_setup_link_generated"] = bool(reset_link)
            if password_setup_email_error:
                response["password_setup_email_error"] = password_setup_email_error
        elif payload.status == "rejected":
            response["rejection_email_sent"] = True
        return response


    listing_ref = db.collection("college_food_listings").document(payload.id)
    listing_doc = listing_ref.get()
    if listing_doc.exists:
        update = {
            "status": payload.status,
            "reviewedAt": datetime.now(timezone.utc).isoformat(),
            "reviewedBy": admin_uid,
        }
        if payload.status == "approved":
            update["approvedAt"] = datetime.now(timezone.utc).isoformat()
        listing_ref.set(update, merge=True)
        return {"message": "Listing status updated", "id": payload.id, "status": payload.status}


    request_ref = db.collection("college_food_requests").document(payload.id)
    request_doc = request_ref.get()
    if request_doc.exists:
        request_data = request_doc.to_dict() or {}
        listing_id = str(request_data.get("listing_id", ""))
        listing_ref = db.collection("college_food_listings").document(listing_id)
        listing_doc = listing_ref.get()
        if not listing_doc.exists:
            raise HTTPException(status_code=404, detail="Listing for request not found")


        listing_data = listing_doc.to_dict() or {}
        requested_quantity = int(request_data.get("quantity", 0) or 0)
        remaining_quantity = int(listing_data.get("remaining_quantity", listing_data.get("quantity", 0)) or 0)


        if payload.status == "approved":
            if remaining_quantity < requested_quantity:
                raise HTTPException(status_code=400, detail="Requested quantity exceeds remaining quantity")
            new_remaining = remaining_quantity - requested_quantity
            listing_ref.set({
                "remaining_quantity": new_remaining,
                "status": "completed" if new_remaining == 0 else listing_data.get("status", "approved"),
                "lastRequestApprovedAt": datetime.now(timezone.utc).isoformat(),
            }, merge=True)


        request_ref.set({
            "status": payload.status,
            "reviewedAt": datetime.now(timezone.utc).isoformat(),
            "reviewedBy": admin_uid,
        }, merge=True)
        return {"message": "Food request updated", "id": payload.id, "status": payload.status}


    raise HTTPException(status_code=404, detail="Exchange request not found")




@app.post("/college/listings")
def create_college_food_listing(
    payload: CollegeFoodListingInput,
    authorization: Optional[str] = Header(default=None),
):
    uid, user_data = _require_role_uid(authorization, {"college"})
    college_key = _resolve_user_college_key(uid, user_data)
    if not payload.food_item.strip():
        raise HTTPException(status_code=400, detail="Food item is required")
    if payload.quantity <= 0:
        raise HTTPException(status_code=400, detail="Quantity must be greater than zero")


    listing_ref = db.collection("college_food_listings").document()
    listing_ref.set({
        "created_by": uid,
        "college_key": college_key,
        "college_name": _user_display_name(user_data),
        "contact_email": user_data.get("email", ""),
        "food_item": payload.food_item.strip(),
        "quantity": payload.quantity,
        "remaining_quantity": payload.quantity,
        "unit": payload.unit.strip() or "plates",
        "pickup_window": payload.pickup_window.strip(),
        "notes": payload.notes.strip(),
        "status": "pending",
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }, merge=True)
    return {"message": "Listing submitted for admin approval", "id": listing_ref.id}




@app.get("/college/listings/mine")
def get_my_college_listings(authorization: Optional[str] = Header(default=None)):
    uid, user_data = _require_role_uid(authorization, {"college"})
    college_key = _resolve_user_college_key(uid, user_data)
    docs = db.collection("college_food_listings").order_by("createdAt", direction="DESCENDING").stream()
    rows = []
    for doc in docs:
        data = doc.to_dict() or {}
        if data.get("created_by") == uid or data.get("college_key") == college_key:
            rows.append({"id": doc.id, **data})
    return rows




@app.get("/college/listings/available")
def get_available_college_listings(authorization: Optional[str] = Header(default=None)):
    uid, user_data = _require_role_uid(authorization, {"college"})
    college_key = _resolve_user_college_key(uid, user_data)
    docs = (
        db.collection("college_food_listings")
        .where("status", "==", "approved")
        .order_by("createdAt", direction="DESCENDING")
        .stream()
    )
    available = []
    for doc in docs:
        data = doc.to_dict() or {}
        if data.get("created_by") == uid:
            continue
        if data.get("college_key") == college_key:
            continue
        if int(data.get("remaining_quantity", 0) or 0) <= 0:
            continue
        available.append({"id": doc.id, **data})
    return available




@app.post("/college/food-requests")
def create_college_food_request(
    payload: CollegeFoodRequestInput,
    authorization: Optional[str] = Header(default=None),
):
    uid, user_data = _require_role_uid(authorization, {"college"})
    to_college_key = _resolve_user_college_key(uid, user_data)
    if payload.quantity <= 0:
        raise HTTPException(status_code=400, detail="Quantity must be greater than zero")


    listing_ref = db.collection("college_food_listings").document(payload.listing_id)
    listing_doc = listing_ref.get()
    if not listing_doc.exists:
        raise HTTPException(status_code=404, detail="Listing not found")


    listing_data = listing_doc.to_dict() or {}
    if listing_data.get("created_by") == uid:
        raise HTTPException(status_code=400, detail="You cannot request your own listing")


    from_college_key = str(listing_data.get("college_key", "")).strip()
    if from_college_key and from_college_key == to_college_key:
        raise HTTPException(status_code=400, detail="You cannot request your own college listing")


    if listing_data.get("status") != "approved":
        raise HTTPException(status_code=400, detail="Listing is not approved yet")


    remaining_quantity = int(listing_data.get("remaining_quantity", 0) or 0)
    if payload.quantity > remaining_quantity:
        raise HTTPException(status_code=400, detail="Requested quantity exceeds available quantity")


    request_ref = db.collection("college_food_requests").document()
    request_ref.set({
        "listing_id": payload.listing_id,
        "food_item": listing_data.get("food_item", ""),
        "quantity": payload.quantity,
        "unit": listing_data.get("unit", "plates"),
        "college_from": listing_data.get("college_name", ""),
        "college_from_uid": listing_data.get("created_by", ""),
        "college_from_key": from_college_key,
        "college_to": _user_display_name(user_data),
        "college_to_uid": uid,
        "college_to_key": to_college_key,
        "notes": payload.notes.strip(),
        "status": "pending",
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }, merge=True)
    return {"message": "Food request submitted", "id": request_ref.id}




@app.get("/college/food-requests")
def get_college_food_requests(authorization: Optional[str] = Header(default=None)):
    uid, user_data = _require_role_uid(authorization, {"college"})
    college_key = _resolve_user_college_key(uid, user_data)
    docs = db.collection("college_food_requests").order_by("createdAt", direction="DESCENDING").stream()
    rows = []
    for doc in docs:
        data = doc.to_dict() or {}
        if (
            data.get("college_to_uid") == uid
            or data.get("college_from_uid") == uid
            or data.get("college_to_key") == college_key
            or data.get("college_from_key") == college_key
        ):
            rows.append({"id": doc.id, **data})
    return rows




# ==========================================
# STUDENT & CANTEEN PUBLIC API
# ==========================================


@app.get("/menu")
def get_menu():
    local_menu = load_data(MENU_MASTER, DEFAULT_MENU)
    if local_menu:
        normalized_menu = []
        for entry in local_menu:
            if not isinstance(entry, dict):
                continue
            name = str(entry.get("name", "")).strip()
            if not name:
                continue
            item_id = str(entry.get("id") or entry.get("item_id") or _normalized_food_key(name)).strip()
            normalized_menu.append(
                {
                    "id": item_id,
                    "item_id": item_id,
                    "name": name,
                    "price": _safe_int(entry.get("price"), 0),
                    "category": str(entry.get("category") or "general").strip().lower() or "general",
                    "approved": bool(entry.get("approved", True)),
                }
            )
        if normalized_menu:
            return normalized_menu

    try:
        docs = db.collection("menu").where("approved", "==", True).stream(timeout=3)
        menu_items = []
        for doc in docs:
            data = doc.to_dict() or {}
            menu_items.append({
                "id": doc.id,
                "item_id": doc.id,
                "name": data.get("name", ""),
                "price": data.get("price", 0),
                "category": data.get("category", "general"),
                "approved": data.get("approved", True),
            })

        if menu_items:
            return menu_items
    except Exception:
        pass

    return DEFAULT_MENU




class CreateMenuItem(BaseModel):
    name: str
    price: int
    category: str = "general"




@app.post("/menu")
def create_menu_item(item: CreateMenuItem):
    name = item.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Menu item name is required")

    category = item.category.strip().lower() if item.category else "general"
    created_at = datetime.now(timezone.utc).isoformat()
    item_id = _normalized_food_key(name) or f"menu-{int(datetime.now().timestamp())}"

    shared_menu = load_data(MENU_MASTER, DEFAULT_MENU)
    shared_menu = [entry for entry in shared_menu if _normalized_food_key(entry.get("name")) != item_id]
    shared_menu.insert(
        0,
        {
            "id": item_id,
            "name": name,
            "price": item.price,
            "category": category,
        },
    )
    save_data(MENU_MASTER, shared_menu)

    db.collection("menu").document(item_id).set(
        {
            "name": name,
            "price": item.price,
            "category": category,
            "approved": True,
            "status": "approved",
            "createdAt": created_at,
            "approvedAt": created_at,
        },
        merge=True,
    )

    return {
        "message": "Menu item added",
        "id": item_id,
    }




class OrderRequest(BaseModel):
    uid: str
    item: str
    price: int
    quantity: int
    category: Optional[str] = None


class BatchOrderItem(BaseModel):
    item: str
    price: int
    quantity: int
    category: Optional[str] = None


class BatchOrderRequest(BaseModel):
    uid: str
    items: List[BatchOrderItem]


class CanteenOperationItem(BaseModel):
    food_item: str
    food_category: Optional[str] = None
    price: int = 0
    predicted_demand: Optional[int] = None
    suggested_preparation: Optional[int] = None
    quantity_prepared: int = 0
    quantity_sold: int = 0
    quantity_wasted: Optional[int] = None
    confidence_score: Optional[float] = None
    confidence_label: Optional[str] = None
    weather_type: Optional[str] = None
    temperature: Optional[int] = None
    notes: str = ""


class CanteenOperationsRequest(BaseModel):
    date: str
    time_slot: str = "11:00-13:00"
    items: List[CanteenOperationItem]




@app.get("/canteen/operations")
def get_canteen_operations(
    date: Optional[str] = None,
    time_slot: Optional[str] = None,
):
    date_key = _normalize_operation_date(date)
    slot = str(time_slot or "11:00-13:00").strip() or "11:00-13:00"

    merged_items = _operations_view_rows(
        date_key=date_key,
        time_slot=slot,
        restrict_to_user=False,
    )

    summary = _operations_summary(merged_items)
    summary.update(
        {
            "items_forecasted": len(merged_items),
            "average_confidence": 0,
            "highest_demand_item": merged_items[0]["food_item"] if merged_items else "N/A",
        }
    )

    return {
        "date": date_key,
        "time_slot": slot,
        "items": merged_items,
        "summary": summary,
        "forecast_summary": {
            "items_forecasted": len(merged_items),
            "average_confidence": 0,
            "highest_demand_item": merged_items[0]["food_item"] if merged_items else "N/A",
            "generated_at": datetime.now().isoformat(),
            "time_slot": slot,
        },
        "formula": "Saved operations are shown directly to avoid rebuilding the forecast on every page open.",
    }


@app.post("/canteen/operations")
def save_canteen_operations(
    payload: CanteenOperationsRequest,
    authorization: Optional[str] = Header(default=None),
):
    uid, user_data = _resolve_canteen_request(authorization)
    date_key = _normalize_operation_date(payload.date)
    slot = str(payload.time_slot or "11:00-13:00").strip() or "11:00-13:00"
    college_key = _resolve_user_college_key(uid, user_data)
    scope_key = college_key or uid

    existing_rows = load_data(OPERATIONS_FILE, DEFAULT_OPERATIONS)
    operations_by_id: Dict[str, Dict[str, Any]] = {}
    for row in existing_rows:
        if isinstance(row, dict) and str(row.get("id", "")).strip():
            operations_by_id[str(row["id"]).strip()] = dict(row)

    saved_count = 0
    removed_count = 0
    resolved_prediction_logs = 0
    operations_to_resolve: List[Dict[str, Any]] = []

    for item in payload.items:
        food_item = str(item.food_item).strip()
        if not food_item:
            continue

        record_id = _operation_record_id(scope_key, date_key, slot, food_item)
        notes = item.notes.strip()
        quantity_prepared = max(_safe_int(item.quantity_prepared), 0)
        quantity_sold = max(_safe_int(item.quantity_sold), 0)
        quantity_wasted = (
            max(_safe_int(item.quantity_wasted), 0)
            if item.quantity_wasted is not None
            else max(quantity_prepared - quantity_sold, 0)
        )
        minimum_prepared = quantity_sold + quantity_wasted
        if minimum_prepared > quantity_prepared:
            quantity_prepared = minimum_prepared

        if quantity_prepared == 0 and quantity_sold == 0 and quantity_wasted == 0 and not notes:
            if record_id in operations_by_id:
                operations_by_id.pop(record_id, None)
                removed_count += 1
            continue

        operation = operations_by_id.get(record_id, {})
        operation.update(
            {
                "id": record_id,
                "date": date_key,
                "time_slot": slot,
                "food_item": food_item,
                "food_category": str(item.food_category or operation.get("food_category") or "general").strip().lower() or "general",
                "price": max(_safe_int(item.price, _safe_int(operation.get("price"))), 0),
                "predicted_demand": _safe_int(item.predicted_demand, _safe_int(operation.get("predicted_demand"))),
                "suggested_preparation": _safe_int(item.suggested_preparation, _safe_int(operation.get("suggested_preparation"))),
                "quantity_prepared": quantity_prepared,
                "quantity_sold": quantity_sold,
                "quantity_wasted": quantity_wasted,
                "confidence_score": float(item.confidence_score if item.confidence_score is not None else operation.get("confidence_score", 0) or 0),
                "confidence_label": str(item.confidence_label or operation.get("confidence_label") or "Low"),
                "weather_type": str(item.weather_type or operation.get("weather_type") or "Sunny"),
                "temperature": _safe_int(item.temperature, _safe_int(operation.get("temperature"), 29)),
                "notes": notes,
                "recorded_by": uid,
                "college_key": college_key,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        operations_by_id[record_id] = operation
        saved_count += 1
        operations_to_resolve.append(operation.copy())
        threading.Thread(
            target=_sync_operation_to_firestore,
            args=(operation.copy(),),
            daemon=True,
        ).start()

    next_rows = list(operations_by_id.values())
    next_rows.sort(
        key=lambda row: (
            str(row.get("date", "")),
            str(row.get("time_slot", "")),
            str(row.get("food_item", "")).lower(),
        ),
        reverse=True,
    )
    save_data(OPERATIONS_FILE, next_rows)

    if operations_to_resolve:
        threading.Thread(
            target=_resolve_operation_logs_async,
            args=(operations_to_resolve,),
            daemon=True,
        ).start()

    scoped_rows = _operations_for_scope(
        date_key=date_key,
        time_slot=slot,
        college_key=college_key,
        uid=uid,
    )
    return {
        "message": "Canteen operations saved",
        "saved_count": saved_count,
        "removed_count": removed_count,
        "resolved_prediction_logs": resolved_prediction_logs,
        "date": date_key,
        "time_slot": slot,
        "summary": _operations_summary(scoped_rows),
    }


@app.post("/order")
def place_order(order: OrderRequest):
    if order.quantity <= 0:
        raise HTTPException(status_code=400, detail="Quantity must be greater than zero")
    if order.price < 0:
        raise HTTPException(status_code=400, detail="Price cannot be negative")

    orders = load_data(ORDERS_FILE, DEFAULT_ORDERS)
    category = str(order.category or "general").strip().lower() or "general"
    orders.append({
        "id": str(len(orders) + 1),
        "uid": order.uid,
        "item": order.item,
        "price": order.price,
        "quantity": order.quantity,
        "category": category,
        "time": pd.Timestamp.now().isoformat(),
    })
    save_data(ORDERS_FILE, orders)
    base_points = max(order.quantity * 10, 10)
    bonus_points = _order_bonus_points(category, order.quantity)
    points_awarded = base_points + bonus_points
    total_points = _increment_user_points(order.uid, points_awarded)
    return {
        "message": "Order placed",
        "base_points": base_points,
        "bonus_points": bonus_points,
        "points_awarded": points_awarded,
        "total_points": total_points,
        "reward": get_rewards(total_points),
    }


@app.post("/order/batch")
def place_order_batch(payload: BatchOrderRequest):
    if not payload.items:
        raise HTTPException(status_code=400, detail="Cart is empty")

    orders = load_data(ORDERS_FILE, DEFAULT_ORDERS)
    next_id = len(orders) + 1
    total_cost = 0
    total_quantity = 0
    total_awarded = 0
    total_bonus = 0
    placed_items = []

    for line in payload.items:
        if line.quantity <= 0:
            raise HTTPException(status_code=400, detail="Quantity must be greater than zero")
        if line.price < 0:
            raise HTTPException(status_code=400, detail="Price cannot be negative")

        category = str(line.category or "general").strip().lower() or "general"
        orders.append({
            "id": str(next_id),
            "uid": payload.uid,
            "item": line.item,
            "price": line.price,
            "quantity": line.quantity,
            "category": category,
            "time": pd.Timestamp.now().isoformat(),
        })
        next_id += 1

        base_points = max(line.quantity * 10, 10)
        bonus_points = _order_bonus_points(category, line.quantity)
        points_awarded = base_points + bonus_points
        total_awarded += points_awarded
        total_bonus += bonus_points
        total_cost += line.price * line.quantity
        total_quantity += line.quantity
        placed_items.append(
            {
                "item": line.item,
                "quantity": line.quantity,
                "price": line.price,
                "category": category,
                "points_awarded": points_awarded,
                "bonus_points": bonus_points,
            }
        )

    save_data(ORDERS_FILE, orders)
    total_points = _increment_user_points(payload.uid, total_awarded)
    return {
        "message": "Order placed",
        "items": placed_items,
        "item_count": len(placed_items),
        "quantity_total": total_quantity,
        "total_cost": total_cost,
        "bonus_points": total_bonus,
        "points_awarded": total_awarded,
        "total_points": total_points,
        "reward": get_rewards(total_points),
    }


@app.get("/student/orders/{uid}")
def get_student_orders(uid: str):
    orders = load_data(ORDERS_FILE, DEFAULT_ORDERS)
    student_orders = [
        order for order in orders if str(order.get("uid", "")).strip() == uid.strip()
    ]
    student_orders.sort(key=lambda order: str(order.get("time", "")), reverse=True)
    return student_orders


@app.get("/student/attendance/{uid}")
def get_student_attendance(uid: str):
    records = _sorted_attendance_records(uid)
    summary = _attendance_summary(records)
    return {
        "records": records,
        **summary,
    }


@app.get("/student/leaderboard")
def get_student_leaderboard():
    leaderboard = []
    try:
        docs = db.collection("users").stream(timeout=3)
        for doc in docs:
            data = doc.to_dict() or {}
            role = str(data.get("role", "")).strip().lower()
            if role not in {"student", "faculty"}:
                continue
            if data.get("isActive") is False:
                continue

            points = _safe_int(data.get("points", data.get("rewardPoints", 0)))
            leaderboard.append(
                {
                    "uid": doc.id,
                    "name": data.get("name", "") or "Campus User",
                    "email": data.get("email", ""),
                    "role": role,
                    "points": points,
                    "reward": get_rewards(points),
                }
            )
    except Exception:
        return []

    leaderboard.sort(
        key=lambda row: (-row["points"], str(row.get("name", "")).lower(), str(row.get("email", "")).lower())
    )

    for index, row in enumerate(leaderboard, start=1):
        row["rank"] = index

    return leaderboard




class AttendanceRequest(BaseModel):
    uid: str
    date: str
    time: str




@app.post("/attendance")
def mark_attendance(att: AttendanceRequest):
    attendance = load_data(ATTENDANCE_FILE, DEFAULT_ATTENDANCE)
    found = next((a for a in attendance if a.get("uid") == att.uid and a.get("date") == att.date), None)
    if found:
        raise HTTPException(status_code=400, detail="Attendance already marked")
    attendance.append({
        "id": str(len(attendance) + 1),
        "uid": att.uid,
        "date": att.date,
        "time": att.time,
    })
    save_data(ATTENDANCE_FILE, attendance)
    points_awarded = 5
    total_points = _increment_user_points(att.uid, points_awarded)
    return {
        "message": "Attendance marked",
        "points_awarded": points_awarded,
        "total_points": total_points,
    }


class UpdateProfileRequest(BaseModel):
    name: str = ""
    phone: str = ""
    department: Optional[str] = None
    college_name: Optional[str] = None
    college_domains: Optional[List[str]] = None


@app.put("/users/profile")
def update_user_profile(
    payload: UpdateProfileRequest,
    authorization: Optional[str] = Header(default=None),
):
    uid = _require_authenticated_uid(authorization)
    user_ref = db.collection("users").document(uid)
    user_doc = user_ref.get()
    if not user_doc.exists:
        raise HTTPException(status_code=404, detail="User profile not found")

    current_data = user_doc.to_dict() or {}
    role = str(current_data.get("role", "")).strip().lower()

    update_payload: Dict[str, Any] = {
        "name": payload.name.strip(),
        "phone": payload.phone.strip(),
        "updatedAt": datetime.now(timezone.utc).isoformat(),
    }

    if role in {"faculty", "canteen"} and payload.department is not None:
        update_payload["department"] = payload.department.strip()

    if role == "college":
        if payload.college_name is not None:
            update_payload["collegeName"] = payload.college_name.strip()
        if payload.college_domains is not None:
            normalized_domains = []
            for domain in payload.college_domains:
                parsed = _normalize_domain(str(domain))
                if parsed and parsed not in normalized_domains:
                    normalized_domains.append(parsed)
            update_payload["collegeDomains"] = normalized_domains
            update_payload["collegeKey"] = _build_college_key(
                str(update_payload.get("collegeName", current_data.get("collegeName", ""))),
                str(current_data.get("email", "")),
                normalized_domains,
            )

    user_ref.set(update_payload, merge=True)
    return {"message": "Profile updated", "profile": update_payload}




class FacultyOrderRequest(BaseModel):
    faculty_id: str
    item_name: str
    unit_price: int
    quantity: int




class FacultyPayRequest(BaseModel):
    faculty_id: str
    order_ids: List[str] = []




class RegisterFcmTokenRequest(BaseModel):
    token: str




class FacultyReminderRequest(BaseModel):
    period: str = "weekly"




def _period_days(period: str) -> int:
    value = period.strip().lower()
    if value == "weekly":
        return 7
    if value == "monthly":
        return 30
    raise HTTPException(status_code=400, detail="Invalid period. Use weekly or monthly")




def _collect_faculty_pending(days: int) -> Dict[str, Dict]:
    now = datetime.now(timezone.utc)
    docs = db.collection("faculty_orders").where("payment_status", "==", "pending").stream()


    by_faculty: Dict[str, Dict] = {}
    for doc in docs:
        data = doc.to_dict() or {}
        created_raw = data.get("createdAt")


        include = True
        if created_raw:
            try:
                created_dt = datetime.fromisoformat(str(created_raw).replace("Z", "+00:00"))
                include = (now - created_dt).days < days
            except Exception:
                include = True


        if not include:
            continue


        faculty_id = data.get("faculty_id")
        if not faculty_id:
            continue


        entry = by_faculty.setdefault(faculty_id, {"total": 0, "order_ids": []})
        entry["total"] += int(data.get("total_amount", 0) or 0)
        entry["order_ids"].append(doc.id)


    return by_faculty




@app.post("/notifications/register-token")
def register_fcm_token(
    payload: RegisterFcmTokenRequest,
    authorization: Optional[str] = Header(default=None),
):
    uid = _require_authenticated_uid(authorization)
    token = payload.token.strip()
    if not token:
        raise HTTPException(status_code=400, detail="Token is required")


    db.collection("users").document(uid).set({
        "fcmToken": token,
        "fcmUpdatedAt": datetime.now(timezone.utc).isoformat(),
    }, merge=True)
    return {"message": "FCM token saved", "uid": uid}




@app.post("/faculty/orders")
def create_faculty_order(payload: FacultyOrderRequest):
    if payload.quantity <= 0:
        raise HTTPException(status_code=400, detail="Quantity must be greater than zero")
    if payload.unit_price < 0:
        raise HTTPException(status_code=400, detail="Price cannot be negative")


    total_amount = payload.unit_price * payload.quantity
    now = datetime.now(timezone.utc)


    doc_ref = db.collection("faculty_orders").document()
    doc_ref.set({
        "faculty_id": payload.faculty_id,
        "items": [
            {
                "name": payload.item_name,
                "unit_price": payload.unit_price,
                "quantity": payload.quantity,
                "line_total": total_amount,
            }
        ],
        "total_amount": total_amount,
        "payment_status": "pending",
        "date": now.date().isoformat(),
        "createdAt": now.isoformat(),
    }, merge=True)


    return {
        "message": "Faculty order created with pending payment",
        "order_id": doc_ref.id,
        "total_amount": total_amount,
        "payment_status": "pending",
    }




@app.get("/faculty/orders/{faculty_id}")
def get_faculty_orders(faculty_id: str, status: str = "pending"):
    query = db.collection("faculty_orders").where("faculty_id", "==", faculty_id)
    if status:
        query = query.where("payment_status", "==", status)


    docs = query.stream()
    orders = []
    total_pending = 0
    for doc in docs:
        data = doc.to_dict() or {}
        row = {
            "order_id": doc.id,
            "faculty_id": data.get("faculty_id"),
            "items": data.get("items", []),
            "total_amount": int(data.get("total_amount", 0) or 0),
            "payment_status": data.get("payment_status", "pending"),
            "date": data.get("date"),
        }
        if row["payment_status"] == "pending":
            total_pending += row["total_amount"]
        orders.append(row)


    return {
        "faculty_id": faculty_id,
        "orders": orders,
        "total_pending": total_pending,
    }




@app.post("/faculty/orders/pay")
def pay_faculty_orders(payload: FacultyPayRequest):
    if payload.order_ids:
        refs = [db.collection("faculty_orders").document(order_id) for order_id in payload.order_ids]
    else:
        docs = db.collection("faculty_orders") \
            .where("faculty_id", "==", payload.faculty_id) \
            .where("payment_status", "==", "pending") \
            .stream()
        refs = [db.collection("faculty_orders").document(doc.id) for doc in docs]


    if not refs:
        return {"message": "No pending faculty orders to settle", "updated": 0}


    now = datetime.now(timezone.utc).isoformat()
    updated = 0
    for ref in refs:
        snapshot = ref.get()
        if not snapshot.exists:
            continue
        data = snapshot.to_dict() or {}
        if data.get("faculty_id") != payload.faculty_id:
            continue
        ref.set({"payment_status": "paid", "paidAt": now}, merge=True)
        updated += 1


    return {"message": "Faculty payment settled", "updated": updated}




@app.get("/faculty/pending-summary/{faculty_id}")
def faculty_pending_summary(faculty_id: str, period: str = "weekly"):
    days = _period_days(period)
    pending = _collect_faculty_pending(days)
    total = int(pending.get(faculty_id, {}).get("total", 0))
    return {
        "faculty_id": faculty_id,
        "period": period,
        "total_pending": total,
        "notification_message": f"You have ₹{total} pending canteen payment this {period}."
    }




@app.post("/admin/faculty-payment-reminders")
def send_faculty_payment_reminders(
    payload: FacultyReminderRequest,
    authorization: Optional[str] = Header(default=None),
):
    _require_admin_uid(authorization)
    days = _period_days(payload.period)
    pending = _collect_faculty_pending(days)


    sent = 0
    skipped = 0
    details = []


    for faculty_id, data in pending.items():
        total = int(data.get("total", 0))
        if total <= 0:
            continue


        user_doc = db.collection("users").document(faculty_id).get()
        user_data = user_doc.to_dict() if user_doc.exists else {}
        token = (user_data or {}).get("fcmToken")
        if not token:
            skipped += 1
            details.append({
                "faculty_id": faculty_id,
                "status": "skipped_no_token",
                "total_pending": total,
            })
            continue


        body = f"You have ₹{total} pending canteen payment this {payload.period}."
        message = firebase_messaging.Message(
            token=token,
            notification=firebase_messaging.Notification(
                title="Faculty Pay-Later Reminder",
                body=body,
            ),
            data={
                "type": "faculty_pay_later_reminder",
                "faculty_id": faculty_id,
                "period": payload.period,
                "total_pending": str(total),
            },
        )


        try:
            firebase_messaging.send(message)
            sent += 1
            details.append({
                "faculty_id": faculty_id,
                "status": "sent",
                "total_pending": total,
            })
        except Exception as exc:
            skipped += 1
            details.append({
                "faculty_id": faculty_id,
                "status": f"failed: {str(exc)}",
                "total_pending": total,
            })


    return {
        "message": "Faculty payment reminders processed",
        "period": payload.period,
        "sent": sent,
        "skipped": skipped,
        "details": details,
    }




# ==========================================
# RETRAIN MODEL
# ==========================================


@app.post("/retrain")
def retrain():
    metrics = train_models()
    return {
        "message": "Model retrained successfully",
        "metrics": metrics,
    }


@app.get("/test-smtp-config")
def test_smtp_config():
    """Test endpoint to verify email environment variables are loaded."""
    return {
        "provider": "brevo",
        "brevo_api_key": "SET" if os.getenv("BREVO_API_KEY") else "NOT_SET",
        "smtp_host": os.getenv("SMTP_HOST", "NOT_SET"),
        "smtp_port": os.getenv("SMTP_PORT", "NOT_SET"),
        "smtp_username": os.getenv("SMTP_USERNAME", "NOT_SET"),
        "smtp_password": "SET" if os.getenv("SMTP_PASSWORD") else "NOT_SET",
        "smtp_from_email": os.getenv("SMTP_FROM_EMAIL", "NOT_SET"),
        "smtp_from_name": os.getenv("SMTP_FROM_NAME", "NOT_SET"),
        "smtp_use_tls": os.getenv("SMTP_USE_TLS", "NOT_SET"),
        "smtp_use_ssl": os.getenv("SMTP_USE_SSL", "NOT_SET"),
    }


@app.get("/debug-signup-requests")
def debug_signup_requests():
    """Debug endpoint to see all signup requests without auth"""
    try:
        requests = list(db.collection("college_signup_requests").stream())
        return {
            "count": len(requests),
            "requests": _serialize_docs(requests)
        }
    except Exception as e:
        return {"error": str(e), "count": 0}

@app.get("/debug-smtp")
async def test_smtp_debug():
    return {
        "smtp_host": os.getenv("SMTP_HOST", "NOT SET"),
        "smtp_port": os.getenv("SMTP_PORT", "NOT SET"),
        "smtp_username": os.getenv("SMTP_USERNAME", "NOT SET"),
        "smtp_password": "***" if os.getenv("SMTP_PASSWORD") else "NOT SET",
        "use_ssl": os.getenv("SMTP_USE_SSL", "NOT SET"),
        "use_tls": os.getenv("SMTP_USE_TLS", "NOT SET"),
    }
