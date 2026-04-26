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
import time
from pathlib import Path
from typing import List, Dict, Optional, Any
from datetime import datetime, timezone, timedelta


from firebase_admin import auth as firebase_auth
from firebase_admin import firestore as admin_firestore
from firebase_admin import messaging as firebase_messaging
from firebase_connect import db


from log_prediction import apply_operation_actuals
from ml_pipeline import (
    build_demand_dashboard,
    build_waste_reduction_trend,
    get_forecast_menu_items,
    get_training_status,
    run_training_cycle,
)
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


def _parse_iso_datetime(value: Any) -> datetime | None:
    raw = str(value or "").strip()
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except Exception:
        return None


def _should_run_auto_retrain(status: dict[str, Any]) -> bool:
    if str(status.get("status") or "").lower() == "running":
        return False

    last_completed = _parse_iso_datetime(status.get("last_completed_at"))
    if last_completed is None:
        return True

    if last_completed.tzinfo is None:
        last_completed = last_completed.replace(tzinfo=timezone.utc)
    now = datetime.now(timezone.utc)
    elapsed_hours = (now - last_completed.astimezone(timezone.utc)).total_seconds() / 3600
    return elapsed_hours >= AUTO_RETRAIN_INTERVAL_HOURS


def _auto_retrain_loop() -> None:
    while True:
        try:
            status = get_training_status()
            if _should_run_auto_retrain(status):
                with _AUTO_RETRAIN_LOCK:
                    refreshed_status = get_training_status()
                    if _should_run_auto_retrain(refreshed_status):
                        run_training_cycle(trigger="auto_scheduler")
        except Exception:
            pass
        time.sleep(AUTO_RETRAIN_CHECK_SECONDS)


@app.on_event("startup")
def start_auto_retraining_worker() -> None:
    global _AUTO_RETRAIN_THREAD_STARTED
    if not AUTO_RETRAIN_ENABLED or _AUTO_RETRAIN_THREAD_STARTED:
        return

    worker = threading.Thread(
        target=_auto_retrain_loop,
        name="auto-retrain-worker",
        daemon=True,
    )
    worker.start()
    _AUTO_RETRAIN_THREAD_STARTED = True


def _extract_bearer_token(authorization: Optional[str]) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid auth token")
    return authorization.split(" ", 1)[1].strip()


def _cached_response(cache_key: str, ttl_seconds: int, builder):
    now = datetime.now(timezone.utc)
    cached_entry = _API_CACHE.get(cache_key)
    if cached_entry:
        expires_at = cached_entry.get("expires_at")
        payload = cached_entry.get("payload")
        if isinstance(expires_at, datetime) and expires_at > now and payload is not None:
            return payload

    payload = builder()
    _API_CACHE[cache_key] = {
        "expires_at": now + timedelta(seconds=ttl_seconds),
        "payload": payload,
    }
    return payload


def _invalidate_cache_prefix(prefix: str) -> None:
    keys_to_remove = [key for key in _API_CACHE if key.startswith(prefix)]
    for key in keys_to_remove:
        _API_CACHE.pop(key, None)


_FIRESTORE_READ_TIMEOUT = 3
DEFAULT_ADMIN_EMAIL = os.getenv("DEFAULT_ADMIN_EMAIL", "CampusCurb30@gmail.com").strip().lower()
COLLEGE_EXCHANGE_PICKUP_HUB_NAME = os.getenv(
    "COLLEGE_EXCHANGE_PICKUP_HUB_NAME",
    "Campus Curb Main Canteen Gate",
).strip()
COLLEGE_EXCHANGE_PICKUP_HUB_ADDRESS = os.getenv(
    "COLLEGE_EXCHANGE_PICKUP_HUB_ADDRESS",
    "Student campus pickup counter for approved surplus collections.",
).strip()
COLLEGE_EXCHANGE_PICKUP_HUB_QUERY = os.getenv(
    "COLLEGE_EXCHANGE_PICKUP_HUB_QUERY",
    COLLEGE_EXCHANGE_PICKUP_HUB_NAME,
).strip()
AUTO_RETRAIN_ENABLED = os.getenv("AUTO_RETRAIN_ENABLED", "true").strip().lower() not in {
    "0",
    "false",
    "no",
}
AUTO_RETRAIN_INTERVAL_HOURS = max(
    int(os.getenv("AUTO_RETRAIN_INTERVAL_HOURS", "168") or 168),
    1,
)
AUTO_RETRAIN_CHECK_SECONDS = max(
    int(os.getenv("AUTO_RETRAIN_CHECK_SECONDS", "1800") or 1800),
    60,
)
_AUTO_RETRAIN_THREAD_STARTED = False
_AUTO_RETRAIN_LOCK = threading.Lock()
FACULTY_CACHE_TTL_SECONDS = max(
    int(os.getenv("FACULTY_CACHE_TTL_SECONDS", "20") or 20),
    5,
)
ANALYTICS_CACHE_TTL_SECONDS = max(
    int(os.getenv("ANALYTICS_CACHE_TTL_SECONDS", "25") or 25),
    5,
)
_API_CACHE: dict[str, dict[str, Any]] = {}




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

    user_data = _resolve_user_profile(uid, decoded)
    if not user_data:
        raise HTTPException(status_code=403, detail="User profile missing")

    if user_data.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Admin role required")


    return uid




def _require_role_uid(authorization: Optional[str], allowed_roles: set[str]) -> tuple[str, Dict]:
    token = _extract_bearer_token(authorization)
    try:
        decoded = firebase_auth.verify_id_token(token)
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid Firebase token") from exc


    uid = decoded.get("uid")
    if not uid:
        raise HTTPException(status_code=401, detail="Invalid token payload")


    user_data = _resolve_user_profile(uid, decoded)
    if not user_data:
        raise HTTPException(status_code=403, detail="User profile missing")

    if user_data.get("role") not in allowed_roles:
        raise HTTPException(status_code=403, detail="Insufficient role")
    if user_data.get("isActive") is False:
        raise HTTPException(status_code=403, detail="Account is inactive")


    return uid, user_data



def _resolve_canteen_request(authorization: Optional[str]) -> tuple[str, Dict[str, Any]]:
    try:
        token = _extract_bearer_token(authorization)
        decoded = firebase_auth.verify_id_token(token)
        uid = str(decoded.get("uid") or "").strip()
        if not uid:
            raise HTTPException(status_code=401, detail="Invalid token payload")

        local_profile = _find_local_user_profile(
            uid,
            email=_normalize_email(decoded.get("email")),
        )
        if local_profile is not None:
            role = str(local_profile.get("role") or "").strip().lower()
            if role in {"canteen", "admin"}:
                return uid, local_profile

        fallback_profile = {
            "uid": uid,
            "email": _normalize_email(decoded.get("email")),
            "name": decoded.get("name") or "Canteen Operator",
            "role": "canteen",
            "isActive": True,
            "seededBy": "canteen_request_fallback",
        }
        _save_local_user_profile(uid, fallback_profile)
        return uid, fallback_profile
    except Exception:
        return "canteen", {"role": "canteen", "isActive": True}




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
    def build_payload():
        from student_analytics import student_behavior
        try:
            return student_behavior()
        except Exception as exc:
            return {
                "most_popular_food": {},
                "most_ordered_food": {"name": "N/A", "orders": 0},
                "food_rankings": [],
                "peak_order_time": None,
                "peak_order_time_details": {"slot": None, "orders": 0},
                "veg_preference": "0.0%",
                "veg_vs_non_veg_ratio": {
                    "veg_count": 0,
                    "non_veg_count": 0,
                    "veg_percentage": 0.0,
                    "non_veg_percentage": 0.0,
                    "display": "N/A",
                },
                "top_students": {},
                "top_students_list": [],
                "total_orders": 0,
                "note": f"Student analytics is temporarily unavailable: {str(exc)}",
            }

    return _cached_response(
        "analytics:student_behavior",
        ANALYTICS_CACHE_TTL_SECONDS,
        build_payload,
    )




@app.get("/prediction-accuracy")
def prediction_accuracy():
    def build_payload():
        from student_analytics import prediction_accuracy_summary
        try:
            return prediction_accuracy_summary()
        except Exception as exc:
            return {
                "overall_accuracy_percentage": 0.0,
                "total_predictions": 0,
                "resolved_predictions": 0,
                "pending_predictions": 0,
                "recent_logs": [],
                "accuracy_by_food": [],
                "note": f"Prediction accuracy is temporarily unavailable: {str(exc)}",
            }

    return _cached_response(
        "analytics:prediction_accuracy",
        ANALYTICS_CACHE_TTL_SECONDS,
        build_payload,
    )


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
    def build_payload():
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
            "Waste After ML": int(report.get("estimated_waste_after_ml", report.get("total_food_wasted", 0))),
            "Sell Through Percentage": f"{int(round(report.get('sell_through_percentage', 0)))}%",
            "Item Waste Breakdown": report.get("item_waste_breakdown", []),
            "Waste Reduction Trend": build_waste_reduction_trend(),
            "Note": report.get("note", ""),
        }

    return _cached_response(
        "analytics:waste_report",
        ANALYTICS_CACHE_TTL_SECONDS,
        build_payload,
    )




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
def demand_dashboard(
    target_date: Optional[str] = None,
    time_slot: Optional[str] = None,
):
    cache_key = f"demand_dashboard:{target_date or 'today'}:{time_slot or 'default'}"
    return _cached_response(
        cache_key,
        ANALYTICS_CACHE_TTL_SECONDS,
        lambda: demand_dashboard_data(
            target_date=target_date,
            time_slot=time_slot,
        ),
    )


@app.get("/ml/overview")
def ml_overview():
    return _cached_response(
        "analytics:ml_overview",
        ANALYTICS_CACHE_TTL_SECONDS,
        get_ml_overview,
    )


@app.get("/ml/training-status")
def ml_training_status():
    return get_training_status()




# ==========================================
# ADMIN WORKFLOW STORAGE + ENDPOINTS
# ==========================================


DATA_DIR = Path("./data")
DATA_DIR.mkdir(exist_ok=True)
MENU_FILE = DATA_DIR / "admin_menu_pending.json"
EXCHANGE_FILE = DATA_DIR / "admin_exchange_requests.json"
COLLEGE_LISTINGS_FILE = DATA_DIR / "college_food_listings.json"
COLLEGE_REQUESTS_FILE = DATA_DIR / "college_food_requests.json"
COLLEGE_SIGNUP_FILE = DATA_DIR / "college_signup_requests.json"
USER_PROFILES_FILE = DATA_DIR / "user_profiles.json"


MENU_MASTER = DATA_DIR / "menu.json"
ORDERS_FILE = DATA_DIR / "orders.json"
FACULTY_ORDERS_FILE = DATA_DIR / "faculty_orders.json"
ATTENDANCE_FILE = DATA_DIR / "attendance.json"
ATTENDANCE_INTENTS_FILE = DATA_DIR / "attendance_intents.json"
OPERATIONS_FILE = DATA_DIR / "canteen_operations.json"
POINTS_CACHE_FILE = DATA_DIR / "user_points_cache.json"
PICKUP_QUEUE_FILE = DATA_DIR / "pickup_queue_status.json"


DEFAULT_MENU_PENDING = []
DEFAULT_FACULTY_ORDERS = []
DEFAULT_PICKUP_QUEUE = []


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
DEFAULT_COLLEGE_LISTINGS = []
DEFAULT_COLLEGE_REQUESTS = []
DEFAULT_COLLEGE_SIGNUPS = []
DEFAULT_USER_PROFILES = {}


DEFAULT_MENU = [
    {"id": "5", "name": "Coffee", "price": 66, "category": "beverage"},
    {"id": "6", "name": "Tea", "price": 63, "category": "beverage"},
    {"id": "8", "name": "Sandwich", "price": 66, "category": "fastfood"},
    {"id": "9", "name": "Noodles", "price": 64, "category": "fastfood"},
    {"id": "10", "name": "Burger", "price": 68, "category": "fastfood"},
    {"id": "11", "name": "Pasta", "price": 67, "category": "fastfood"},
    {"id": "12", "name": "Coke diet", "price": 40, "category": "beverage"},
]


DEFAULT_ORDERS = []
DEFAULT_ATTENDANCE = []
DEFAULT_ATTENDANCE_INTENTS = []
DEFAULT_OPERATIONS = []
DEFAULT_POINTS_CACHE = {}
LOGIN_ATTEMPTS_FILE = DATA_DIR / "auth_login_attempts.json"
DEFAULT_LOGIN_ATTEMPTS = []
ADMIN_ACTIONS_FILE = DATA_DIR / "admin_action_logs.json"
DEFAULT_ADMIN_ACTIONS = []




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


def _load_faculty_orders_local() -> List[Dict[str, Any]]:
    rows = load_data(FACULTY_ORDERS_FILE, DEFAULT_FACULTY_ORDERS)
    normalized_rows: List[Dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        items = row.get("items", [])
        normalized_rows.append(
            {
                "order_id": str(row.get("order_id") or row.get("id") or "").strip(),
                "faculty_id": str(row.get("faculty_id", "")).strip(),
                "items": items if isinstance(items, list) else [],
                "total_amount": _safe_int(row.get("total_amount"), 0),
                "payment_status": str(row.get("payment_status") or "pending").strip().lower() or "pending",
                "date": row.get("date"),
                "createdAt": row.get("createdAt"),
                "order_token": row.get("order_token"),
                "pickup_status": str(row.get("pickup_status") or "pending").strip().lower() or "pending",
                "source": "local",
            }
        )
    return normalized_rows


def _save_faculty_orders_local(rows: List[Dict[str, Any]]) -> None:
    save_data(FACULTY_ORDERS_FILE, rows)


def _load_pickup_queue_statuses() -> List[Dict[str, Any]]:
    rows = load_data(PICKUP_QUEUE_FILE, DEFAULT_PICKUP_QUEUE)
    normalized_rows: List[Dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        normalized_rows.append(
            {
                "entry_key": str(row.get("entry_key") or "").strip(),
                "order_token": str(row.get("order_token") or "").strip(),
                "order_id": str(row.get("order_id") or "").strip(),
                "source": str(row.get("source") or "").strip().lower() or "student",
                "pickup_status": str(row.get("pickup_status") or "pending").strip().lower() or "pending",
                "updatedAt": row.get("updatedAt"),
            }
        )
    return normalized_rows


def _save_pickup_queue_statuses(rows: List[Dict[str, Any]]) -> None:
    save_data(PICKUP_QUEUE_FILE, rows)


def _pickup_entry_key(source: str, order_id: str, order_token: str) -> str:
    normalized_source = str(source or "student").strip().lower() or "student"
    normalized_order_id = str(order_id or "").strip()
    normalized_token = str(order_token or "").strip()
    identifier = normalized_token or normalized_order_id
    return f"{normalized_source}:{identifier}"


def _pickup_status_map() -> Dict[str, Dict[str, Any]]:
    return {
        row["entry_key"]: row
        for row in _load_pickup_queue_statuses()
        if str(row.get("entry_key") or "").strip()
    }


def _sync_menu_item_to_firestore(item_id: str, payload: Dict[str, Any]) -> None:
    try:
        db.collection("menu").document(item_id).set(payload, merge=True)
    except Exception:
        pass


def _sync_menu_pending_status_to_firestore(
    item_id: str,
    payload: Dict[str, Any],
    *,
    delete_after: bool = False,
) -> None:
    try:
        ref = db.collection("menu_pending").document(item_id)
        ref.set(payload, merge=True)
        if delete_after:
            ref.delete()
    except Exception:
        pass


def _merge_faculty_orders(
    local_rows: List[Dict[str, Any]],
    remote_rows: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    merged_by_id: Dict[str, Dict[str, Any]] = {}
    for row in local_rows + remote_rows:
        order_id = str(row.get("order_id") or row.get("id") or "").strip()
        if not order_id:
            continue
        merged_by_id[order_id] = {
            **merged_by_id.get(order_id, {}),
            **row,
            "order_id": order_id,
        }
    merged_rows = list(merged_by_id.values())
    merged_rows.sort(
        key=lambda row: str(row.get("createdAt") or row.get("date") or ""),
        reverse=True,
    )
    return merged_rows


def _local_faculty_orders_for_user(
    faculty_id: str,
    status: str = "pending",
) -> List[Dict[str, Any]]:
    normalized_faculty_id = str(faculty_id or "").strip()
    normalized_status = str(status or "").strip().lower()
    rows = []
    for row in _load_faculty_orders_local():
        if row.get("faculty_id") != normalized_faculty_id:
            continue
        if normalized_status and str(row.get("payment_status") or "").strip().lower() != normalized_status:
            continue
        rows.append(row)
    rows.sort(
        key=lambda row: str(row.get("createdAt") or row.get("date") or ""),
        reverse=True,
    )
    return rows


def _collect_faculty_pending_local(days: int) -> Dict[str, Dict]:
    now = datetime.now(timezone.utc)
    by_faculty: Dict[str, Dict] = {}
    for row in _load_faculty_orders_local():
        if row.get("payment_status") != "pending":
            continue
        created_raw = row.get("createdAt")
        include = True
        if created_raw:
            try:
                created_dt = datetime.fromisoformat(str(created_raw).replace("Z", "+00:00"))
                include = (now - created_dt).days < days
            except Exception:
                include = True
        if not include:
            continue
        faculty_id = row.get("faculty_id")
        if not faculty_id:
            continue
        entry = by_faculty.setdefault(faculty_id, {"total": 0, "order_ids": []})
        entry["total"] += _safe_int(row.get("total_amount"), 0)
        entry["order_ids"].append(row.get("order_id"))
    return by_faculty


def _today_key_from_datetime(now_value: datetime) -> str:
    return now_value.strftime("%Y-%m-%d")


def _time_key_from_datetime(now_value: datetime) -> str:
    return now_value.strftime("%H:%M")


def _build_order_batch_id(uid: str, now_value: datetime) -> str:
    clean_uid = str(uid or "student").strip() or "student"
    return f"order-{clean_uid[:6]}-{int(now_value.timestamp())}"


def _build_order_token(batch_id: str, now_value: datetime) -> str:
    suffix = str(batch_id).split("-")[-1][-4:]
    return f"CC-{now_value.strftime('%m%d')}-{suffix}"


def _save_attendance_intent(uid: str, date_key: str, time_key: str) -> Dict[str, Any]:
    intents = load_data(ATTENDANCE_INTENTS_FILE, DEFAULT_ATTENDANCE_INTENTS)
    existing = next(
        (
            record for record in intents
            if str(record.get("uid", "")).strip() == uid.strip()
            and str(record.get("date", "")).strip() == date_key
        ),
        None,
    )
    if existing:
        existing["time"] = time_key
        existing["status"] = "pending_checkout"
        save_data(ATTENDANCE_INTENTS_FILE, intents)
        return existing

    intent = {
        "id": str(len(intents) + 1),
        "uid": uid,
        "date": date_key,
        "time": time_key,
        "status": "pending_checkout",
    }
    intents.append(intent)
    save_data(ATTENDANCE_INTENTS_FILE, intents)
    return intent


def _clear_attendance_intent(uid: str, date_key: str) -> None:
    intents = load_data(ATTENDANCE_INTENTS_FILE, DEFAULT_ATTENDANCE_INTENTS)
    remaining = [
        record
        for record in intents
        if not (
            str(record.get("uid", "")).strip() == uid.strip()
            and str(record.get("date", "")).strip() == date_key
        )
    ]
    if len(remaining) != len(intents):
        save_data(ATTENDANCE_INTENTS_FILE, remaining)


def _mark_attendance_from_checkout(uid: str, date_key: str, time_key: str, batch_id: str) -> tuple[bool, int]:
    attendance = load_data(ATTENDANCE_FILE, DEFAULT_ATTENDANCE)
    already_marked = any(
        str(record.get("uid", "")).strip() == uid.strip()
        and str(record.get("date", "")).strip() == date_key
        for record in attendance
        if isinstance(record, dict)
    )
    if already_marked:
        _clear_attendance_intent(uid, date_key)
        return False, 0

    attendance.append(
        {
            "id": str(len(attendance) + 1),
            "uid": uid,
            "date": date_key,
            "time": time_key,
            "source": "order_checkout",
            "batch_id": batch_id,
        }
    )
    save_data(ATTENDANCE_FILE, attendance)
    _clear_attendance_intent(uid, date_key)
    return True, 5


def _normalize_email(value: Any) -> str:
    return str(value or "").strip().lower()


def _load_local_user_profiles() -> Dict[str, Dict[str, Any]]:
    rows = load_data(USER_PROFILES_FILE, DEFAULT_USER_PROFILES)
    return rows if isinstance(rows, dict) else {}


def _save_local_user_profiles(rows: Dict[str, Dict[str, Any]]) -> None:
    save_data(USER_PROFILES_FILE, rows)


def _save_local_user_profile(uid: str, profile: Dict[str, Any]) -> None:
    normalized_uid = str(uid or "").strip()
    if not normalized_uid:
        return
    rows = _load_local_user_profiles()
    next_profile = dict(rows.get(normalized_uid, {}))
    next_profile.update(profile or {})
    next_profile["uid"] = normalized_uid
    if "email" in next_profile:
        next_profile["email"] = _normalize_email(next_profile.get("email"))
    rows[normalized_uid] = next_profile
    _save_local_user_profiles(rows)


def _find_local_user_profile(uid: str, *, email: str = "") -> Optional[Dict[str, Any]]:
    rows = _load_local_user_profiles()
    normalized_uid = str(uid or "").strip()
    if normalized_uid:
        by_uid = rows.get(normalized_uid)
        if isinstance(by_uid, dict):
            profile = dict(by_uid)
            profile["uid"] = normalized_uid
            return profile


    normalized_email = _normalize_email(email)
    if not normalized_email:
        return None


    for stored_uid, profile in rows.items():
        if not isinstance(profile, dict):
            continue
        if _normalize_email(profile.get("email")) != normalized_email:
            continue
        resolved_profile = dict(profile)
        resolved_profile["uid"] = normalized_uid or str(stored_uid)
        if normalized_uid and normalized_uid != str(stored_uid):
            _save_local_user_profile(normalized_uid, resolved_profile)
        return resolved_profile
    return None


def _fetch_firestore_user_profile(uid: str) -> Optional[Dict[str, Any]]:
    normalized_uid = str(uid or "").strip()
    if not normalized_uid:
        return None
    try:
        user_doc = db.collection("users").document(normalized_uid).get(
            timeout=_FIRESTORE_READ_TIMEOUT,
            retry=None,
        )
    except Exception as exc:
        print(f"Warning: Firestore user lookup failed for {normalized_uid}: {exc}")
        return None
    if not user_doc.exists:
        return None
    profile = user_doc.to_dict() or {}
    _save_local_user_profile(normalized_uid, profile)
    return dict(profile)


def _resolve_user_profile(uid: str, decoded: Optional[Dict[str, Any]] = None) -> Optional[Dict[str, Any]]:
    normalized_uid = str(uid or "").strip()
    normalized_email = _normalize_email((decoded or {}).get("email"))


    local_profile = _find_local_user_profile(normalized_uid, email=normalized_email)
    if local_profile is not None:
        return local_profile


    firestore_profile = _fetch_firestore_user_profile(normalized_uid)
    if firestore_profile is not None:
        return firestore_profile


    if normalized_email and normalized_email == DEFAULT_ADMIN_EMAIL:
        fallback_profile = {
            "email": normalized_email,
            "name": "CampusCurb Admin",
            "role": "admin",
            "department": "",
            "points": 0,
            "isActive": True,
            "createdAt": datetime.now(timezone.utc).isoformat(),
            "seededBy": "default_admin_fallback",
        }
        _save_local_user_profile(normalized_uid, fallback_profile)
        return fallback_profile
    return None


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
    try:
        forecast_rows = demand_dashboard_data(
            target_date=date_key,
            time_slot=time_slot,
        ).get("dashboard", [])
        forecast_by_food = {
            _normalized_food_key(row.get("food_item")): row
            for row in forecast_rows
            if isinstance(row, dict)
        }
    except Exception:
        forecast_by_food = {}

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
        forecast = forecast_by_food.get(_normalized_food_key(food_item), {})
        existing = rows_by_food.pop(_normalized_food_key(food_item), None)
        if existing is not None:
            confidence_score = float(existing.get("confidence_score", 0) or 0)
            merged_items.append(
                {
                    "food_item": existing.get("food_item", food_item),
                    "food_category": existing.get(
                        "food_category", menu_item.get("category", "general")
                    ),
                    "predicted_demand": _safe_int(existing.get("predicted_demand")) or _safe_int(forecast.get("predicted_demand")),
                    "suggested_preparation": _safe_int(existing.get("suggested_preparation")) or _safe_int(forecast.get("suggested_preparation")),
                    "expected_waste": _safe_int(existing.get("quantity_wasted")) or _safe_int(forecast.get("expected_waste")),
                    "recent_average_sales": _safe_int(existing.get("recent_average_sales")) or _safe_int(forecast.get("recent_average_sales")),
                    "historical_average_sales": _safe_int(existing.get("historical_average_sales")) or _safe_int(forecast.get("historical_average_sales")),
                    "historical_preparation_average": _safe_int(existing.get("historical_preparation_average")) or _safe_int(forecast.get("historical_preparation_average")),
                    "historical_waste_average": _safe_int(existing.get("historical_waste_average")) or _safe_int(forecast.get("historical_waste_average")),
                    "confidence_score": confidence_score or forecast.get("confidence_score", 0),
                    "confidence_label": existing.get("confidence_label") if confidence_score else forecast.get("confidence_label", "Low"),
                    "trend_direction": existing.get("trend_direction") or forecast.get("trend_direction", "stable"),
                    "trend_reason": existing.get(
                        "trend_reason"
                    ) or forecast.get(
                        "trend_reason", "Saved canteen record for this slot."
                    ),
                    "recommended_action": existing.get(
                        "recommended_action"
                    ) or forecast.get(
                        "recommended_action", "Review manually."
                    ),
                    "time_slot": existing.get("time_slot", time_slot),
                    "target_date": existing.get("date", date_key),
                    "weather_type": existing.get("weather_type") or forecast.get("weather_type", "Sunny"),
                    "temperature": _safe_int(existing.get("temperature"), _safe_int(forecast.get("temperature"), 29)),
                    "model_name": existing.get("model_name") or forecast.get("model_name", "Saved Record"),
                    "feature_snapshot": existing.get("feature_snapshot") or forecast.get("feature_snapshot", {}),
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
                "predicted_demand": _safe_int(forecast.get("predicted_demand")),
                "suggested_preparation": _safe_int(forecast.get("suggested_preparation")),
                "expected_waste": _safe_int(forecast.get("expected_waste")),
                "recent_average_sales": _safe_int(forecast.get("recent_average_sales")),
                "historical_average_sales": _safe_int(forecast.get("historical_average_sales")),
                "historical_preparation_average": _safe_int(forecast.get("historical_preparation_average")),
                "historical_waste_average": _safe_int(forecast.get("historical_waste_average")),
                "confidence_score": forecast.get("confidence_score", 0),
                "confidence_label": forecast.get("confidence_label", "Low"),
                "trend_direction": forecast.get("trend_direction", "stable"),
                "trend_reason": forecast.get("trend_reason", "No saved operations yet."),
                "recommended_action": forecast.get("recommended_action", "Enter today's operations."),
                "time_slot": time_slot,
                "target_date": date_key,
                "weather_type": forecast.get("weather_type", "Sunny"),
                "temperature": _safe_int(forecast.get("temperature"), 29),
                "model_name": forecast.get("model_name", "Saved Record"),
                "feature_snapshot": forecast.get("feature_snapshot", {}),
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


class AdminActionLogInput(BaseModel):
    admin_id: str
    action: str
    target_id: str = ""
    details: str = ""
    timestamp: str = ""




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


@app.post("/admin/log-action")
def log_admin_action(
    payload: AdminActionLogInput,
    request: Request,
    authorization: Optional[str] = Header(default=None),
):
    try:
        resolved_admin_uid = _require_admin_uid(authorization)
    except Exception:
        resolved_admin_uid = str(payload.admin_id or "").strip()

    action_logs = load_data(ADMIN_ACTIONS_FILE, DEFAULT_ADMIN_ACTIONS)
    action_logs.append({
        "timestamp": payload.timestamp.strip() or datetime.now(timezone.utc).isoformat(),
        "admin_id": resolved_admin_uid,
        "action": payload.action.strip(),
        "target_id": payload.target_id.strip(),
        "details": payload.details.strip(),
        "ip": request.client.host if request.client else "unknown",
        "user_agent": request.headers.get("user-agent", "unknown"),
    })
    if len(action_logs) > 2000:
        action_logs = action_logs[-2000:]
    save_data(ADMIN_ACTIONS_FILE, action_logs)
    return {"message": "Admin action logged"}




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


    _save_local_user_profile(created_user.uid, user_doc)
    try:
        db.collection("users").document(created_user.uid).set(
            user_doc,
            merge=True,
            timeout=_FIRESTORE_READ_TIMEOUT,
            retry=None,
        )
    except Exception as exc:
        print(f"Warning: user profile saved locally only for {email}: {exc}")


    return {
        "message": "User created",
        "uid": created_user.uid,
        "email": email,
        "role": role,
    }




@app.get("/admin/menu-pending")
def admin_menu_pending():
    def normalize_local_pending() -> list[dict[str, Any]]:
        pending_items = []
        for entry in load_data(MENU_FILE, DEFAULT_MENU_PENDING):
            if not isinstance(entry, dict):
                continue
            status = str(entry.get("status") or "pending").strip().lower() or "pending"
            if status != "pending":
                continue
            item_id = str(entry.get("id", "")).strip()
            if not item_id:
                continue
            pending_items.append(
                {
                    "id": item_id,
                    "item_id": item_id,
                    "name": entry.get("name", ""),
                    "price": entry.get("price", 0),
                    "category": entry.get("category", "general"),
                    "status": status,
                    "approved": entry.get("approved", False),
                    "createdAt": entry.get("createdAt"),
                    "requestedBy": entry.get("requestedBy"),
                }
            )
        pending_items.sort(key=lambda item: str(item.get("createdAt", "")), reverse=True)
        return pending_items

    return _cached_response(
        "admin:menu_pending",
        FACULTY_CACHE_TTL_SECONDS,
        normalize_local_pending,
    )




class MenuAction(BaseModel):
    id: str




@app.post("/admin/menu-approve")
def admin_menu_approve(payload: MenuAction):
    local_pending = load_data(MENU_FILE, DEFAULT_MENU_PENDING)
    pending_data = {}
    local_match = next(
        (
            entry for entry in local_pending
            if isinstance(entry, dict) and str(entry.get("id", "")).strip() == payload.id
        ),
        None,
    )
    if local_match:
        pending_data = dict(local_match)

    if not pending_data:
        raise HTTPException(status_code=404, detail="Menu item not found")


    shared_menu = load_data(MENU_MASTER, DEFAULT_MENU)
    shared_menu = [
        entry
        for entry in shared_menu
        if _normalized_food_key(entry.get("name")) != payload.id
    ]
    shared_menu.insert(
        0,
        {
            "id": payload.id,
            "name": pending_data.get("name", ""),
            "price": pending_data.get("price", 0),
            "category": pending_data.get("category", "general"),
        },
    )
    save_data(MENU_MASTER, shared_menu)

    approved_at = datetime.now(timezone.utc).isoformat()
    menu_payload = {
            "name": pending_data.get("name", ""),
            "price": pending_data.get("price", 0),
            "category": pending_data.get("category", "general"),
            "approved": True,
            "status": "approved",
            "approvedAt": approved_at,
        }
    pending_cleanup_payload = {
        "status": "approved",
        "approved": True,
        "approvedAt": approved_at,
    }

    updated_local_pending = [
        entry
        for entry in local_pending
        if not (
            isinstance(entry, dict)
            and str(entry.get("id", "")).strip() == payload.id
        )
    ]
    save_data(MENU_FILE, updated_local_pending)
    _invalidate_cache_prefix("shared:menu")
    _invalidate_cache_prefix("admin:menu_pending")
    _invalidate_cache_prefix("analytics:ml_overview")
    _invalidate_cache_prefix("demand_dashboard:")

    threading.Thread(
        target=_sync_menu_item_to_firestore,
        args=(payload.id, menu_payload),
        daemon=True,
    ).start()
    threading.Thread(
        target=_sync_menu_pending_status_to_firestore,
        args=(payload.id, pending_cleanup_payload),
        kwargs={"delete_after": True},
        daemon=True,
    ).start()

    return {"message": "Menu item approved", "id": payload.id}




@app.post("/admin/menu-reject")
def admin_menu_reject(payload: MenuAction):
    local_pending = load_data(MENU_FILE, DEFAULT_MENU_PENDING)
    found_local = False
    rejected_at = datetime.now(timezone.utc).isoformat()
    for entry in local_pending:
        if isinstance(entry, dict) and str(entry.get("id", "")).strip() == payload.id:
            entry["status"] = "rejected"
            entry["rejectedAt"] = rejected_at
            entry["approved"] = False
            found_local = True

    if not found_local:
        raise HTTPException(status_code=404, detail="Menu item not found")
    save_data(MENU_FILE, local_pending)
    _invalidate_cache_prefix("admin:menu_pending")
    _invalidate_cache_prefix("analytics:ml_overview")

    threading.Thread(
        target=_sync_menu_pending_status_to_firestore,
        args=(
            payload.id,
            {
                "status": "rejected",
                "rejectedAt": rejected_at,
                "approved": False,
            },
        ),
        daemon=True,
    ).start()

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


class CollegeAccountActivationInput(BaseModel):
    email: str = ""




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
    preferred_pickup_time: str = ""




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


def _firestore_docs(collection_name: str, *, status: Optional[str] = None) -> List[Dict]:
    try:
        query = db.collection(collection_name)
        if status is not None:
            query = query.where("status", "==", status)
        docs = query.order_by("createdAt", direction="DESCENDING").stream(
            timeout=_FIRESTORE_READ_TIMEOUT,
            retry=None,
        )
        return _serialize_docs(docs)
    except Exception as exc:
        print(f"Warning: using local exchange fallback for {collection_name}: {exc}")
        return []


def _exchange_slug(value: Any) -> str:
    cleaned = re.sub(r"[^a-z0-9]+", "-", str(value or "").lower()).strip("-")
    return cleaned or "item"


def _unique_by_id(rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    merged: Dict[str, Dict[str, Any]] = {}
    for row in rows:
        row_id = str(row.get("id", "")).strip()
        if not row_id:
            continue
        merged[row_id] = row
    return sorted(
        merged.values(),
        key=lambda item: str(item.get("createdAt") or item.get("updated_at") or ""),
        reverse=True,
    )


def _local_signup_requests() -> List[Dict[str, Any]]:
    rows = load_data(COLLEGE_SIGNUP_FILE, DEFAULT_COLLEGE_SIGNUPS)
    return rows if isinstance(rows, list) else []


def _save_local_signup_requests(rows: List[Dict[str, Any]]) -> None:
    save_data(COLLEGE_SIGNUP_FILE, rows)


def _latest_signup_request_by_email(email: str) -> Optional[Dict[str, Any]]:
    normalized_email = _normalize_email(email)
    if not normalized_email:
        return None
    matches = [
        dict(row)
        for row in _local_signup_requests()
        if _normalize_email(row.get("email")) == normalized_email
    ]
    if not matches:
        return None
    matches.sort(key=lambda item: str(item.get("createdAt") or ""), reverse=True)
    return matches[0]


def _save_updated_signup_request(signup_id: str, updates: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    rows = _local_signup_requests()
    updated_row = None
    next_rows = []
    for row in rows:
        if str(row.get("id")) != signup_id:
            next_rows.append(row)
            continue
        updated_row = dict(row)
        updated_row.update(updates or {})
        next_rows.append(updated_row)
    if updated_row is not None:
        _save_local_signup_requests(next_rows)
    return updated_row


def _college_signup_profile(signup_data: Dict[str, Any], *, uid: str, signup_id: str) -> Dict[str, Any]:
    email = _normalize_email(signup_data.get("email"))
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


    return {
        "name": signup_data.get("contact_name", "") or college_name,
        "email": email,
        "role": "college",
        "department": "",
        "collegeName": college_name,
        "collegeDomains": normalized_domains,
        "collegeKey": college_key,
        "points": 0,
        "isActive": True,
        "provisionedFromSignupRequestId": signup_id,
    }


def _is_self_service_activation_fallback(exc: Exception) -> bool:
    message = str(exc).lower()
    return (
        "invalid_grant" in message
        or "invalid jwt signature" in message
        or "metadata from plugin failed" in message
        or "the default firebase app does not exist" in message
    )


def _base_local_listings() -> List[Dict[str, Any]]:
    rows = load_data(COLLEGE_LISTINGS_FILE, DEFAULT_COLLEGE_LISTINGS)
    return rows if isinstance(rows, list) else []


def _save_base_local_listings(rows: List[Dict[str, Any]]) -> None:
    save_data(COLLEGE_LISTINGS_FILE, rows)


def _local_food_requests() -> List[Dict[str, Any]]:
    rows = load_data(COLLEGE_REQUESTS_FILE, DEFAULT_COLLEGE_REQUESTS)
    return rows if isinstance(rows, list) else []


def _save_local_food_requests(rows: List[Dict[str, Any]]) -> None:
    save_data(COLLEGE_REQUESTS_FILE, rows)


def _generated_waste_listings() -> List[Dict[str, Any]]:
    operations = load_data(OPERATIONS_FILE, DEFAULT_OPERATIONS)
    if not isinstance(operations, list):
        return []

    latest_date = ""
    for row in operations:
        if not isinstance(row, dict):
            continue
        if str(row.get("recorded_by", "")) == "demo-seed":
            continue
        wasted = _safe_int(row.get("quantity_wasted"))
        if wasted <= 0:
            continue
        date = str(row.get("date") or "").strip()
        if date and date > latest_date:
            latest_date = date

    generated: List[Dict[str, Any]] = []
    for row in operations:
        if not isinstance(row, dict):
            continue
        if str(row.get("recorded_by", "")) == "demo-seed":
            continue
        wasted = _safe_int(row.get("quantity_wasted"))
        if wasted <= 0:
            continue
        food_item = str(row.get("food_item") or "Surplus food").strip()
        date = str(row.get("date") or datetime.now(timezone.utc).date().isoformat())
        if latest_date and date != latest_date:
            continue
        time_slot = str(row.get("time_slot") or "today")
        operation_id = str(row.get("id") or f"{date}|{time_slot}|{food_item}")
        listing_id = f"waste|{_exchange_slug(operation_id)}"
        generated.append(
            {
                "id": listing_id,
                "source": "canteen_waste",
                "source_operation_id": operation_id,
                "created_by": str(row.get("recorded_by") or "canteen"),
                "college_key": str(row.get("college_key") or "campus-canteen"),
                "college_name": "Campus Curb Canteen",
                "contact_email": "",
                "food_item": food_item,
                "quantity": wasted,
                "remaining_quantity": wasted,
                "unit": "portions",
                "pickup_window": f"{date} • {time_slot}",
                "pickup_location_name": COLLEGE_EXCHANGE_PICKUP_HUB_NAME,
                "pickup_location_address": COLLEGE_EXCHANGE_PICKUP_HUB_ADDRESS,
                "pickup_map_query": COLLEGE_EXCHANGE_PICKUP_HUB_QUERY,
                "notes": "Auto-created from canteen waste log for inter-college sharing.",
                "status": "live",
                "createdAt": str(row.get("updated_at") or datetime.now(timezone.utc).isoformat()),
                "source_date": date,
                "source_time_slot": time_slot,
                "confidence_label": str(row.get("confidence_label") or ""),
            }
        )
    return sorted(
        generated,
        key=lambda item: (
            str(item.get("source_date") or ""),
            str(item.get("source_time_slot") or ""),
            _safe_int(item.get("remaining_quantity")),
        ),
        reverse=True,
    )


def _local_exchange_listings(include_generated: bool = True) -> List[Dict[str, Any]]:
    stored = _base_local_listings()
    if not include_generated:
        return stored
    stored_ids = {str(row.get("id")) for row in stored if isinstance(row, dict)}
    generated = [
        row for row in _generated_waste_listings() if str(row.get("id")) not in stored_ids
    ]
    return _unique_by_id([*generated, *stored])


def _save_or_update_local_listing(listing: Dict[str, Any]) -> None:
    rows = _base_local_listings()
    listing_id = str(listing.get("id", "")).strip()
    next_rows = [row for row in rows if str(row.get("id")) != listing_id]
    next_rows.append(listing)
    _save_base_local_listings(next_rows)


def _find_local_listing(listing_id: str) -> Optional[Dict[str, Any]]:
    for row in _local_exchange_listings():
        if str(row.get("id")) == listing_id:
            return row
    return None


def _update_local_listing_status(listing_id: str, status: str, admin_uid: str) -> Optional[Dict[str, Any]]:
    listing = _find_local_listing(listing_id)
    if listing is None:
        return None
    listing = dict(listing)
    listing["status"] = status
    listing["reviewedAt"] = datetime.now(timezone.utc).isoformat()
    listing["reviewedBy"] = admin_uid
    if status == "approved":
        listing["approvedAt"] = datetime.now(timezone.utc).isoformat()
    _save_or_update_local_listing(listing)
    return listing


def _save_or_update_local_food_request(request: Dict[str, Any]) -> None:
    rows = _local_food_requests()
    request_id = str(request.get("id", "")).strip()
    next_rows = [row for row in rows if str(row.get("id")) != request_id]
    next_rows.append(request)
    _save_local_food_requests(next_rows)


def _find_local_food_request(request_id: str) -> Optional[Dict[str, Any]]:
    for row in _local_food_requests():
        if str(row.get("id")) == request_id:
            return row
    return None


def _public_exchange_summary() -> Dict[str, int]:
    listings = _local_exchange_listings()
    requests = _local_food_requests()
    return {
        "pending_surplus_listings": sum(1 for item in listings if item.get("status") == "pending"),
        "approved_surplus_listings": sum(1 for item in listings if item.get("status") == "approved"),
        "pending_food_requests": sum(1 for item in requests if item.get("status") == "pending"),
        "completed_food_requests": sum(1 for item in requests if item.get("status") == "approved"),
    }


def _review_signup_request_record(
    signup_data: Dict[str, Any],
    *,
    signup_id: str,
    admin_uid: str,
    status: str,
    rejection_note: str = "",
) -> Dict[str, Any]:
    email = str(signup_data.get("email", "")).strip().lower()
    response = {"message": "Signup request updated", "id": signup_id, "status": status}

    if status == "approved":
        if not email:
            raise HTTPException(status_code=400, detail="Signup request is missing email")

        college_name = str(signup_data.get("college_name", "")).strip()

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
                if _is_self_service_activation_fallback(exc):
                    response["message"] = (
                        "Signup approved. Firebase admin provisioning is unavailable, "
                        "so the college must activate the account from the portal."
                    )
                    response["provisioned_email"] = email
                    response["activation_required"] = True
                    response["password_setup_email_sent"] = False
                    response["password_setup_link_generated"] = False
                    return response
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
            if _is_self_service_activation_fallback(exc):
                response["message"] = (
                    "Signup approved. Firebase admin password setup is unavailable, "
                    "so the college must activate the account from the portal."
                )
                response["provisioned_email"] = email
                response["activation_required"] = True
                response["password_setup_email_sent"] = False
                response["password_setup_link_generated"] = False
                return response
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

        college_profile = _college_signup_profile(signup_data, uid=auth_user.uid, signup_id=signup_id)
        college_profile["createdAt"] = datetime.now(timezone.utc).isoformat()
        college_profile["createdBy"] = admin_uid
        _save_local_user_profile(auth_user.uid, college_profile)
        profile_saved_locally_only = False
        try:
            db.collection("users").document(auth_user.uid).set(
                college_profile,
                merge=True,
                timeout=_FIRESTORE_READ_TIMEOUT,
                retry=None,
            )
        except Exception as exc:
            profile_saved_locally_only = True
            print(f"Warning: college profile saved locally only for {email}: {exc}")

        response["provisioned_email"] = email
        response["auth_user_created"] = created_new_auth_user
        response["password_setup_email_sent"] = password_setup_email_sent
        response["password_setup_link_generated"] = bool(reset_link)
        response["profile_saved_locally_only"] = profile_saved_locally_only
        if password_setup_email_error:
            response["password_setup_email_error"] = password_setup_email_error
        return response

    if status == "rejected" and email:
        college_name = str(signup_data.get("college_name", "")).strip()
        note = rejection_note or "No reason provided."
        try:
            _send_college_rejection_email(email, college_name, note)
            response["rejection_email_sent"] = True
        except Exception as exc:
            print(f"Warning: Failed to send rejection email to {email}: {str(exc)}")
            response["rejection_email_sent"] = False
            response["rejection_email_error"] = str(exc)
    return response




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


    existing_local = [
        row
        for row in _local_signup_requests()
        if str(row.get("email", "")).lower() == email and row.get("status") == "pending"
    ]
    if existing_local:
        raise HTTPException(status_code=400, detail="A signup request is already pending for this email")

    local_id = f"signup|{_exchange_slug(email)}|{int(datetime.now(timezone.utc).timestamp())}"
    signup_payload = {
        "id": local_id,
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
    }
    rows = [row for row in _local_signup_requests() if str(row.get("id")) != local_id]
    rows.append(signup_payload)
    _save_local_signup_requests(rows)
    return {"message": "College signup request submitted", "id": local_id}


@app.get("/college/signup-status")
def get_college_signup_status(email: str):
    normalized_email = _normalize_email(email)
    if not normalized_email:
        raise HTTPException(status_code=400, detail="Email is required")


    signup = _latest_signup_request_by_email(normalized_email)
    if signup is None:
        raise HTTPException(status_code=404, detail="No college signup request found for this email")


    return {
        "id": signup.get("id"),
        "email": normalized_email,
        "status": signup.get("status", "pending"),
        "college_name": signup.get("college_name", ""),
        "contact_name": signup.get("contact_name", ""),
        "activation_required": signup.get("status") == "approved",
    }


@app.post("/college/activate-account")
def activate_college_account(
    payload: CollegeAccountActivationInput,
    authorization: Optional[str] = Header(default=None),
):
    token = _extract_bearer_token(authorization)
    try:
        decoded = firebase_auth.verify_id_token(token)
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid Firebase token") from exc


    uid = decoded.get("uid")
    email = _normalize_email(payload.email or decoded.get("email"))
    if not uid or not email:
        raise HTTPException(status_code=401, detail="Invalid token payload")


    signup = _latest_signup_request_by_email(email)
    if signup is None:
        raise HTTPException(status_code=404, detail="No signup request found for this email")


    status = str(signup.get("status", "")).strip().lower()
    if status != "approved":
        if status == "pending":
            raise HTTPException(status_code=403, detail="Your signup request is still pending admin approval")
        if status == "rejected":
            raise HTTPException(status_code=403, detail="Your signup request was rejected by admin")
        raise HTTPException(status_code=403, detail="Your signup request is not approved")


    now_iso = datetime.now(timezone.utc).isoformat()
    college_profile = _college_signup_profile(signup, uid=uid, signup_id=str(signup.get("id", "")))
    college_profile["createdAt"] = str(signup.get("createdAt") or now_iso)
    college_profile["createdBy"] = str(signup.get("reviewedBy", "self-service"))
    college_profile["activatedAt"] = now_iso
    _save_local_user_profile(uid, college_profile)


    profile_saved_locally_only = False
    try:
        db.collection("users").document(uid).set(
            college_profile,
            merge=True,
            timeout=_FIRESTORE_READ_TIMEOUT,
            retry=None,
        )
    except Exception as exc:
        profile_saved_locally_only = True
        print(f"Warning: activated college profile saved locally only for {email}: {exc}")


    updated_signup = _save_updated_signup_request(
        str(signup.get("id", "")),
        {
            "activatedAt": now_iso,
            "activatedUid": uid,
            "activatedVia": "self-service",
        },
    ) or signup


    return {
        "message": "College account activated",
        "id": updated_signup.get("id"),
        "email": email,
        "uid": uid,
        "profile_saved_locally_only": profile_saved_locally_only,
    }


@app.get("/admin/exchange-requests")
def admin_exchange_requests(authorization: Optional[str] = Header(default=None)):
    _require_admin_uid(authorization)
    signup_requests = _unique_by_id(_local_signup_requests())
    listings = _unique_by_id(_local_exchange_listings())
    food_requests = _unique_by_id(_local_food_requests())
    return {
        "signup_requests": signup_requests,
        "pending_listings": listings,
        "food_requests": food_requests,
        "summary": _public_exchange_summary(),
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
    try:
        signup_doc = signup_ref.get(timeout=_FIRESTORE_READ_TIMEOUT, retry=None)
    except Exception:
        signup_doc = None
    if signup_doc is not None and signup_doc.exists:
        signup_data = signup_doc.to_dict() or {}
        response = _review_signup_request_record(
            signup_data,
            signup_id=payload.id,
            admin_uid=admin_uid,
            status=payload.status,
            rejection_note=payload.rejection_note or "",
        )

        try:
            signup_ref.set({
                "status": payload.status,
                "reviewedAt": datetime.now(timezone.utc).isoformat(),
                "reviewedBy": admin_uid,
                "rejectionNote": payload.rejection_note or "",
            }, merge=True, timeout=_FIRESTORE_READ_TIMEOUT, retry=None)
        except Exception as exc:
            print(f"Warning: signup status sync failed for {payload.id}: {exc}")
        return response

    local_signups = _local_signup_requests()
    local_signup = next((row for row in local_signups if str(row.get("id")) == payload.id), None)
    if local_signup is not None:
        response = _review_signup_request_record(
            local_signup,
            signup_id=payload.id,
            admin_uid=admin_uid,
            status=payload.status,
            rejection_note=payload.rejection_note or "",
        )
        local_signup["status"] = payload.status
        local_signup["reviewedAt"] = datetime.now(timezone.utc).isoformat()
        local_signup["reviewedBy"] = admin_uid
        local_signup["rejectionNote"] = payload.rejection_note or ""
        _save_local_signup_requests(local_signups)
        return response

    listing_ref = db.collection("college_food_listings").document(payload.id)
    try:
        listing_doc = listing_ref.get(timeout=_FIRESTORE_READ_TIMEOUT, retry=None)
    except Exception:
        listing_doc = None
    if listing_doc is not None and listing_doc.exists:
        update = {
            "status": payload.status,
            "reviewedAt": datetime.now(timezone.utc).isoformat(),
            "reviewedBy": admin_uid,
        }
        if payload.status == "approved":
            update["approvedAt"] = datetime.now(timezone.utc).isoformat()
        try:
            listing_ref.set(update, merge=True, timeout=_FIRESTORE_READ_TIMEOUT, retry=None)
        except Exception as exc:
            print(f"Warning: listing status sync failed for {payload.id}: {exc}")
        return {"message": "Listing status updated", "id": payload.id, "status": payload.status}

    local_listing = _update_local_listing_status(payload.id, payload.status, admin_uid)
    if local_listing is not None:
        return {"message": "Listing status updated", "id": payload.id, "status": payload.status}

    request_ref = db.collection("college_food_requests").document(payload.id)
    try:
        request_doc = request_ref.get(timeout=_FIRESTORE_READ_TIMEOUT, retry=None)
    except Exception:
        request_doc = None
    if request_doc is not None and request_doc.exists:
        request_data = request_doc.to_dict() or {}
        listing_id = str(request_data.get("listing_id", ""))
        listing_ref = db.collection("college_food_listings").document(listing_id)
        listing_doc = listing_ref.get(timeout=_FIRESTORE_READ_TIMEOUT, retry=None)
        if not listing_doc.exists:
            raise HTTPException(status_code=404, detail="Listing for request not found")


        listing_data = listing_doc.to_dict() or {}
        requested_quantity = int(request_data.get("quantity", 0) or 0)
        remaining_quantity = int(listing_data.get("remaining_quantity", listing_data.get("quantity", 0)) or 0)


        if payload.status == "approved":
            if remaining_quantity < requested_quantity:
                raise HTTPException(status_code=400, detail="Requested quantity exceeds remaining quantity")
            new_remaining = remaining_quantity - requested_quantity
            try:
                listing_ref.set({
                    "remaining_quantity": new_remaining,
                    "status": "completed" if new_remaining == 0 else listing_data.get("status", "approved"),
                    "lastRequestApprovedAt": datetime.now(timezone.utc).isoformat(),
                }, merge=True, timeout=_FIRESTORE_READ_TIMEOUT, retry=None)
            except Exception as exc:
                print(f"Warning: listing quantity sync failed for {listing_id}: {exc}")


        try:
            request_ref.set({
                "status": payload.status,
                "reviewedAt": datetime.now(timezone.utc).isoformat(),
                "reviewedBy": admin_uid,
            }, merge=True, timeout=_FIRESTORE_READ_TIMEOUT, retry=None)
        except Exception as exc:
            print(f"Warning: food request status sync failed for {payload.id}: {exc}")
        return {"message": "Food request updated", "id": payload.id, "status": payload.status}

    local_request = _find_local_food_request(payload.id)
    if local_request is not None:
        local_request = dict(local_request)
        listing_id = str(local_request.get("listing_id", ""))
        listing = _find_local_listing(listing_id)
        if listing is None:
            raise HTTPException(status_code=404, detail="Listing for request not found")

        requested_quantity = _safe_int(local_request.get("quantity"))
        remaining_quantity = _safe_int(listing.get("remaining_quantity"), _safe_int(listing.get("quantity")))
        if payload.status == "approved":
            if remaining_quantity < requested_quantity:
                raise HTTPException(status_code=400, detail="Requested quantity exceeds remaining quantity")
            listing = dict(listing)
            listing["remaining_quantity"] = remaining_quantity - requested_quantity
            listing["status"] = "completed" if listing["remaining_quantity"] == 0 else listing.get("status", "approved")
            listing["lastRequestApprovedAt"] = datetime.now(timezone.utc).isoformat()
            _save_or_update_local_listing(listing)

        local_request["status"] = payload.status
        local_request["reviewedAt"] = datetime.now(timezone.utc).isoformat()
        local_request["reviewedBy"] = admin_uid
        _save_or_update_local_food_request(local_request)
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


    local_id = f"listing|{college_key or uid}|{_exchange_slug(payload.food_item)}|{int(datetime.now(timezone.utc).timestamp())}"
    listing_payload = {
        "id": local_id,
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
    }
    doc_id = local_id
    try:
        listing_ref = db.collection("college_food_listings").document()
        listing_ref.set({k: v for k, v in listing_payload.items() if k != "id"}, merge=True)
        doc_id = listing_ref.id
        listing_payload["id"] = doc_id
    except Exception as exc:
        print(f"Warning: college listing saved locally only: {exc}")

    _save_or_update_local_listing(listing_payload)
    return {"message": "Listing submitted for admin approval", "id": doc_id}




@app.get("/college/listings/mine")
def get_my_college_listings(authorization: Optional[str] = Header(default=None)):
    uid, user_data = _require_role_uid(authorization, {"college"})
    college_key = _resolve_user_college_key(uid, user_data)
    rows = []
    for data in _local_exchange_listings():
        if data.get("created_by") == uid or data.get("college_key") == college_key:
            rows.append(data)
    return _unique_by_id(rows)




@app.get("/college/listings/available")
def get_available_college_listings(authorization: Optional[str] = Header(default=None)):
    uid, user_data = _require_role_uid(authorization, {"college"})
    college_key = _resolve_user_college_key(uid, user_data)
    available = []
    for data in _local_exchange_listings():
        source = str(data.get("source", "")).strip().lower()
        status = str(data.get("status", "")).strip().lower()
        is_canteen_waste = source == "canteen_waste"
        if is_canteen_waste:
            if status in {"rejected", "completed"}:
                continue
        elif status != "approved":
            continue
        if data.get("created_by") == uid:
            continue
        if data.get("college_key") == college_key:
            continue
        if int(data.get("remaining_quantity", 0) or 0) <= 0:
            continue
        available.append(data)
    return sorted(
        _unique_by_id(available),
        key=lambda item: (
            1 if str(item.get("source", "")).strip().lower() == "canteen_waste" else 0,
            str(item.get("createdAt") or ""),
        ),
        reverse=True,
    )




@app.post("/college/food-requests")
def create_college_food_request(
    payload: CollegeFoodRequestInput,
    authorization: Optional[str] = Header(default=None),
):
    uid, user_data = _require_role_uid(authorization, {"college"})
    to_college_key = _resolve_user_college_key(uid, user_data)
    if payload.quantity <= 0:
        raise HTTPException(status_code=400, detail="Quantity must be greater than zero")


    listing_data = _find_local_listing(payload.listing_id) or {}
    listing_is_firestore = False
    listing_ref = None
    if not listing_data:
        listing_ref = db.collection("college_food_listings").document(payload.listing_id)
        listing_doc = None
        try:
            listing_doc = listing_ref.get(timeout=_FIRESTORE_READ_TIMEOUT, retry=None)
        except Exception:
            listing_doc = None
        listing_is_firestore = bool(listing_doc is not None and listing_doc.exists)
        listing_data = (listing_doc.to_dict() or {}) if listing_is_firestore else {}
    if not listing_data:
        raise HTTPException(status_code=404, detail="Listing not found")

    if listing_data.get("created_by") == uid:
        raise HTTPException(status_code=400, detail="You cannot request your own listing")


    from_college_key = str(listing_data.get("college_key", "")).strip()
    if from_college_key and from_college_key == to_college_key:
        raise HTTPException(status_code=400, detail="You cannot request your own college listing")

    source = str(listing_data.get("source", "")).strip().lower()
    status = str(listing_data.get("status", "")).strip().lower()
    is_canteen_waste = source == "canteen_waste"
    if is_canteen_waste:
        if status in {"rejected", "completed"}:
            raise HTTPException(status_code=400, detail="Listing is not available anymore")
    elif status != "approved":
        raise HTTPException(status_code=400, detail="Listing is not approved yet")


    remaining_quantity = int(listing_data.get("remaining_quantity", 0) or 0)
    if payload.quantity > remaining_quantity:
        raise HTTPException(status_code=400, detail="Requested quantity exceeds available quantity")


    local_id = f"request|{_exchange_slug(payload.listing_id)}|{to_college_key or uid}|{int(datetime.now(timezone.utc).timestamp())}"
    request_payload = {
        "id": local_id,
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
        "preferred_pickup_time": payload.preferred_pickup_time.strip(),
        "pickup_location_name": str(listing_data.get("pickup_location_name") or COLLEGE_EXCHANGE_PICKUP_HUB_NAME),
        "pickup_location_address": str(listing_data.get("pickup_location_address") or COLLEGE_EXCHANGE_PICKUP_HUB_ADDRESS),
        "pickup_map_query": str(listing_data.get("pickup_map_query") or COLLEGE_EXCHANGE_PICKUP_HUB_QUERY),
        "notes": payload.notes.strip(),
        "status": "pending",
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }
    doc_id = local_id
    if listing_is_firestore:
        try:
            request_ref = db.collection("college_food_requests").document()
            request_ref.set({k: v for k, v in request_payload.items() if k != "id"}, merge=True)
            doc_id = request_ref.id
            request_payload["id"] = doc_id
        except Exception as exc:
            print(f"Warning: college food request saved locally only: {exc}")

    _save_or_update_local_food_request(request_payload)
    return {"message": "Food request submitted", "id": doc_id}




@app.get("/college/food-requests")
def get_college_food_requests(authorization: Optional[str] = Header(default=None)):
    uid, user_data = _require_role_uid(authorization, {"college"})
    college_key = _resolve_user_college_key(uid, user_data)
    rows = []
    for data in _local_food_requests():
        if (
            data.get("college_to_uid") == uid
            or data.get("college_from_uid") == uid
            or data.get("college_to_key") == college_key
            or data.get("college_from_key") == college_key
        ):
            rows.append(data)
    return _unique_by_id(rows)




# ==========================================
# STUDENT & CANTEEN PUBLIC API
# ==========================================


@app.get("/menu")
def get_menu():
    def normalize_local_menu() -> list[dict[str, Any]]:
        local_menu = load_data(MENU_MASTER, DEFAULT_MENU)
        normalized_menu = []
        for entry in local_menu:
            if not isinstance(entry, dict):
                continue
            name = str(entry.get("name", "")).strip()
            if not name:
                continue
            item_id = str(
                entry.get("id") or entry.get("item_id") or _normalized_food_key(name)
            ).strip()
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
        return normalized_menu or DEFAULT_MENU

    return _cached_response(
        "shared:menu",
        FACULTY_CACHE_TTL_SECONDS,
        normalize_local_menu,
    )




class CreateMenuItem(BaseModel):
    name: str
    price: int
    category: str = "general"
    auto_approve: bool = True
    requested_by: Optional[str] = None




@app.post("/menu")
def create_menu_item(item: CreateMenuItem):
    name = item.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Menu item name is required")

    category = item.category.strip().lower() if item.category else "general"
    created_at = datetime.now(timezone.utc).isoformat()
    item_id = _normalized_food_key(name) or f"menu-{int(datetime.now().timestamp())}"

    if not item.auto_approve:
        pending_items = load_data(MENU_FILE, DEFAULT_MENU_PENDING)
        pending_items = [
            entry
            for entry in pending_items
            if not (
                isinstance(entry, dict)
                and _normalized_food_key(entry.get("name")) == item_id
                and str(entry.get("status", "pending")).strip().lower() == "pending"
            )
        ]
        pending_payload = {
            "id": item_id,
            "name": name,
            "price": item.price,
            "category": category,
            "status": "pending",
            "approved": False,
            "requestedBy": item.requested_by or "canteen",
            "createdAt": created_at,
        }
        pending_items.insert(0, pending_payload)
        save_data(MENU_FILE, pending_items)

        try:
            db.collection("menu_pending").document(item_id).set(pending_payload, merge=True)
        except Exception:
            pass

        _invalidate_cache_prefix("admin:menu_pending")
        _invalidate_cache_prefix("analytics:ml_overview")
        _invalidate_cache_prefix("demand_dashboard:")

        return {
            "message": "Menu item submitted for approval",
            "id": item_id,
            "status": "pending",
        }

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

    _invalidate_cache_prefix("shared:menu")
    _invalidate_cache_prefix("admin:menu_pending")
    _invalidate_cache_prefix("analytics:ml_overview")
    _invalidate_cache_prefix("demand_dashboard:")

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

    def build_payload():
        merged_items = _operations_view_rows(
            date_key=date_key,
            time_slot=slot,
            restrict_to_user=False,
        )
        average_confidence = round(
            sum(float(row.get("confidence_score", 0) or 0) for row in merged_items)
            / len(merged_items),
            2,
        ) if merged_items else 0

        summary = _operations_summary(merged_items)
        summary.update(
            {
                "items_forecasted": len(merged_items),
                "average_confidence": average_confidence,
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
                "average_confidence": average_confidence,
                "highest_demand_item": merged_items[0]["food_item"] if merged_items else "N/A",
                "generated_at": datetime.now().isoformat(),
                "time_slot": slot,
            },
            "formula": "Saved operations are shown directly to avoid rebuilding the forecast on every page open.",
        }

    return _cached_response(
        f"canteen:operations:{date_key}:{slot}",
        FACULTY_CACHE_TTL_SECONDS,
        build_payload,
    )


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

    _invalidate_cache_prefix("analytics:waste_report")
    _invalidate_cache_prefix(f"canteen:operations:{date_key}:{slot}")
    _invalidate_cache_prefix("analytics:prediction_accuracy")
    _invalidate_cache_prefix("analytics:ml_overview")

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

    now_local = datetime.now()
    today_key = _today_key_from_datetime(now_local)
    time_key = _time_key_from_datetime(now_local)
    batch_id = _build_order_batch_id(order.uid, now_local)
    order_token = _build_order_token(batch_id, now_local)

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
        "date": today_key,
        "batch_id": batch_id,
        "order_token": order_token,
    })
    save_data(ORDERS_FILE, orders)
    _invalidate_cache_prefix("analytics:student_behavior")
    _invalidate_cache_prefix(f"student:orders:{order.uid}")
    _invalidate_cache_prefix(f"student:attendance:{order.uid}")
    _invalidate_cache_prefix("student:leaderboard")
    _invalidate_cache_prefix("analytics:ml_overview")
    _invalidate_cache_prefix("canteen:order_queue")
    attendance_marked, attendance_points_awarded = _mark_attendance_from_checkout(
        order.uid,
        today_key,
        time_key,
        batch_id,
    )
    base_points = max(order.quantity * 10, 10)
    bonus_points = _order_bonus_points(category, order.quantity)
    points_awarded = base_points + bonus_points + attendance_points_awarded
    total_points = _increment_user_points(order.uid, points_awarded)
    return {
        "message": "Order placed",
        "order_batch_id": batch_id,
        "order_token": order_token,
        "base_points": base_points,
        "bonus_points": bonus_points,
        "points_awarded": base_points + bonus_points,
        "attendance_marked": attendance_marked,
        "attendance_points_awarded": attendance_points_awarded,
        "total_points": total_points,
        "reward": get_rewards(total_points),
        "counter_message": f"Show order ID {order_token} at the canteen counter.",
    }


@app.post("/order/batch")
def place_order_batch(payload: BatchOrderRequest):
    if not payload.items:
        raise HTTPException(status_code=400, detail="Cart is empty")

    # Checkout is the commit point for a student visit:
    # 1) place order lines
    # 2) mark attendance for today (if not already marked)
    now_local = datetime.now()
    today_key = _today_key_from_datetime(now_local)
    time_key = _time_key_from_datetime(now_local)
    batch_id = _build_order_batch_id(payload.uid, now_local)
    order_token = _build_order_token(batch_id, now_local)

    orders = load_data(ORDERS_FILE, DEFAULT_ORDERS)
    next_id = len(orders) + 1
    total_cost = 0
    total_quantity = 0
    total_awarded = 0
    total_bonus = 0
    placed_items = []

    attendance_marked, attendance_points_awarded = _mark_attendance_from_checkout(
        payload.uid,
        today_key,
        time_key,
        batch_id,
    )

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
            "date": today_key,
            "batch_id": batch_id,
            "order_token": order_token,
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
    _invalidate_cache_prefix("analytics:student_behavior")
    _invalidate_cache_prefix(f"student:orders:{payload.uid}")
    _invalidate_cache_prefix(f"student:attendance:{payload.uid}")
    _invalidate_cache_prefix("student:leaderboard")
    _invalidate_cache_prefix("analytics:ml_overview")
    _invalidate_cache_prefix("canteen:order_queue")
    total_points = _increment_user_points(
        payload.uid,
        total_awarded + attendance_points_awarded,
    )
    return {
        "message": "Order placed",
        "order_batch_id": batch_id,
        "order_token": order_token,
        "items": placed_items,
        "item_count": len(placed_items),
        "quantity_total": total_quantity,
        "total_cost": total_cost,
        "bonus_points": total_bonus,
        "points_awarded": total_awarded,
        "attendance_marked": attendance_marked,
        "attendance_points_awarded": attendance_points_awarded,
        "attendance_date": today_key,
        "total_points": total_points,
        "reward": get_rewards(total_points),
        "counter_message": f"Show order ID {order_token} at the canteen counter.",
    }


@app.get("/student/orders/{uid}")
def get_student_orders(uid: str):
    def build_payload():
        orders = load_data(ORDERS_FILE, DEFAULT_ORDERS)
        student_orders = [
            order for order in orders if str(order.get("uid", "")).strip() == uid.strip()
        ]
        student_orders.sort(key=lambda order: str(order.get("time", "")), reverse=True)
        return student_orders

    return _cached_response(
        f"student:orders:{uid}",
        FACULTY_CACHE_TTL_SECONDS,
        build_payload,
    )


@app.get("/student/attendance/{uid}")
def get_student_attendance(uid: str):
    def build_payload():
        records = _sorted_attendance_records(uid)
        summary = _attendance_summary(records)
        return {
            "records": records,
            **summary,
        }

    return _cached_response(
        f"student:attendance:{uid}",
        FACULTY_CACHE_TTL_SECONDS,
        build_payload,
    )


@app.get("/student/leaderboard")
def get_student_leaderboard():
    def build_payload():
        profiles = load_data(USER_PROFILES_FILE, DEFAULT_USER_PROFILES)
        points_cache = _load_points_cache()
        leaderboard = []
        if isinstance(profiles, dict):
            for uid, data in profiles.items():
                if not isinstance(data, dict):
                    continue
                role = str(data.get("role", "")).strip().lower()
                if role not in {"student", "faculty"}:
                    continue
                if data.get("isActive") is False:
                    continue
                points = _safe_int(points_cache.get(uid, data.get("points", data.get("rewardPoints", 0))))
                leaderboard.append(
                    {
                        "uid": uid,
                        "name": data.get("name", "") or "Campus User",
                        "email": data.get("email", ""),
                        "role": role,
                        "points": points,
                        "reward": get_rewards(points),
                    }
                )

        leaderboard.sort(
            key=lambda row: (-row["points"], str(row.get("name", "")).lower(), str(row.get("email", "")).lower())
        )

        for index, row in enumerate(leaderboard, start=1):
            row["rank"] = index
        return leaderboard

    return _cached_response(
        "student:leaderboard",
        FACULTY_CACHE_TTL_SECONDS,
        build_payload,
    )




class AttendanceRequest(BaseModel):
    uid: str
    date: str
    time: str




@app.post("/attendance")
def mark_attendance(att: AttendanceRequest):
    attendance = load_data(ATTENDANCE_FILE, DEFAULT_ATTENDANCE)
    found = next((a for a in attendance if a.get("uid") == att.uid and a.get("date") == att.date), None)
    if found:
        return {
            "message": "Attendance already confirmed for this date",
            "intent_saved": False,
            "attendance_confirmed": True,
            "points_awarded": 0,
            "total_points": _current_points_from_cache(att.uid),
        }

    _save_attendance_intent(att.uid, att.date, att.time)
    _invalidate_cache_prefix(f"student:attendance:{att.uid}")
    return {
        "message": "Attendance intent saved. Checkout an order to confirm attendance.",
        "intent_saved": True,
        "attendance_confirmed": False,
        "points_awarded": 0,
        "total_points": _current_points_from_cache(att.uid),
        "next_step": "Add items to cart and checkout to confirm attendance.",
    }


class UpdateProfileRequest(BaseModel):
    name: str = ""
    phone: str = ""
    department: Optional[str] = None
    college_name: Optional[str] = None
    college_domains: Optional[List[str]] = None


@app.get("/users/profile")
def get_user_profile(authorization: Optional[str] = Header(default=None)):
    token = _extract_bearer_token(authorization)
    try:
        decoded = firebase_auth.verify_id_token(token)
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid Firebase token") from exc


    uid = decoded.get("uid")
    if not uid:
        raise HTTPException(status_code=401, detail="Invalid token payload")


    user_data = _resolve_user_profile(uid, decoded)
    if user_data is None:
        raise HTTPException(status_code=404, detail="User profile not found")
    return {"uid": uid, "profile": user_data}


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




class PickupQueueStatusRequest(BaseModel):
    source: str
    pickup_status: str
    order_token: Optional[str] = None
    order_id: Optional[str] = None


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
    by_faculty: Dict[str, Dict] = {}
    local_rows = _load_faculty_orders_local()
    for row in local_rows:
        if row.get("payment_status") != "pending":
            continue
        created_raw = row.get("createdAt")
        include = True
        if created_raw:
            try:
                created_dt = datetime.fromisoformat(str(created_raw).replace("Z", "+00:00"))
                include = (now - created_dt).days < days
            except Exception:
                include = True
        if not include:
            continue
        faculty_id = row.get("faculty_id")
        if not faculty_id:
            continue
        entry = by_faculty.setdefault(faculty_id, {"total": 0, "order_ids": []})
        entry["total"] += _safe_int(row.get("total_amount"), 0)
        entry["order_ids"].append(row.get("order_id"))

    try:
        docs = db.collection("faculty_orders").where("payment_status", "==", "pending").stream(timeout=3)
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
            order_id = doc.id
            if order_id in entry["order_ids"]:
                continue
            entry["total"] += int(data.get("total_amount", 0) or 0)
            entry["order_ids"].append(order_id)
    except Exception:
        pass


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




def _load_remote_faculty_orders() -> List[Dict[str, Any]]:
    remote_orders: List[Dict[str, Any]] = []
    try:
        docs = db.collection("faculty_orders").stream(timeout=3)
        for doc in docs:
            data = doc.to_dict() or {}
            remote_orders.append(
                {
                    "order_id": doc.id,
                    "faculty_id": data.get("faculty_id"),
                    "items": data.get("items", []),
                    "total_amount": int(data.get("total_amount", 0) or 0),
                    "payment_status": data.get("payment_status", "pending"),
                    "date": data.get("date"),
                    "createdAt": data.get("createdAt"),
                    "order_token": data.get("order_token"),
                    "pickup_status": data.get("pickup_status", "pending"),
                    "source": "remote",
                }
            )
    except Exception:
        remote_orders = []
    return remote_orders


def _build_student_queue_entries() -> List[Dict[str, Any]]:
    status_map = _pickup_status_map()
    rows = load_data(ORDERS_FILE, DEFAULT_ORDERS)
    grouped: Dict[str, Dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        row_id = str(row.get("id") or "").strip()
        order_token = str(row.get("order_token") or "").strip()
        batch_id = str(row.get("batch_id") or "").strip()
        entry_id = batch_id or order_token or row_id or f"student-{row_id}"
        if not entry_id:
            continue
        normalized_order_id = batch_id or row_id or entry_id
        display_token = order_token or (f"Order #{row_id}" if row_id else entry_id)

        entry = grouped.setdefault(
            entry_id,
            {
                "source": "student",
                "entry_id": entry_id,
                "order_id": normalized_order_id,
                "order_token": order_token or None,
                "display_token": display_token,
                "user_id": str(row.get("uid") or "").strip(),
                "createdAt": row.get("time"),
                "date": row.get("date"),
                "items": [],
                "total_quantity": 0,
                "total_amount": 0,
                "payment_status": "paid",
            },
        )
        quantity = _safe_int(row.get("quantity"), 0)
        price = _safe_int(row.get("price"), 0)
        line_total = quantity * price
        entry["items"].append(
            {
                "name": str(row.get("item") or "Item").strip() or "Item",
                "quantity": quantity,
                "unit_price": price,
                "line_total": line_total,
            }
        )
        entry["total_quantity"] += quantity
        entry["total_amount"] += line_total
        if not entry.get("createdAt") and row.get("time"):
            entry["createdAt"] = row.get("time")
        if not entry.get("date") and row.get("date"):
            entry["date"] = row.get("date")
        if not entry.get("order_token") and order_token:
            entry["order_token"] = order_token
        if not entry.get("display_token") and display_token:
            entry["display_token"] = display_token

    entries: List[Dict[str, Any]] = []
    for entry in grouped.values():
        entry_key = _pickup_entry_key(
            "student",
            str(entry.get("order_id") or ""),
            str(entry.get("order_token") or ""),
        )
        status_row = status_map.get(entry_key, {})
        entry["pickup_status"] = str(
            status_row.get("pickup_status")
            or entry.get("pickup_status")
            or "pending"
        ).strip().lower() or "pending"
        entry["updatedAt"] = status_row.get("updatedAt") or entry.get("createdAt")
        entries.append(entry)
    return entries


def _build_faculty_queue_entries() -> List[Dict[str, Any]]:
    status_map = _pickup_status_map()
    faculty_orders = _load_faculty_orders_local()
    entries: List[Dict[str, Any]] = []
    for row in faculty_orders:
        order_id = str(row.get("order_id") or "").strip()
        order_token = str(row.get("order_token") or "").strip()
        if not order_id and not order_token:
            continue
        items = row.get("items", [])
        normalized_items = []
        total_quantity = 0
        for item in items if isinstance(items, list) else []:
            quantity = _safe_int(item.get("quantity"), 0)
            unit_price = _safe_int(item.get("unit_price"), 0)
            line_total = _safe_int(item.get("line_total"), quantity * unit_price)
            total_quantity += quantity
            normalized_items.append(
                {
                    "name": str(item.get("name") or "Item").strip() or "Item",
                    "quantity": quantity,
                    "unit_price": unit_price,
                    "line_total": line_total,
                }
            )
        entry_key = _pickup_entry_key("faculty", order_id, order_token)
        status_row = status_map.get(entry_key, {})
        entries.append(
            {
                "source": "faculty",
                "entry_id": order_id or order_token,
                "order_id": order_id,
                "order_token": order_token,
                "user_id": str(row.get("faculty_id") or "").strip(),
                "createdAt": row.get("createdAt"),
                "date": row.get("date"),
                "items": normalized_items,
                "total_quantity": total_quantity,
                "total_amount": _safe_int(row.get("total_amount"), 0),
                "payment_status": str(row.get("payment_status") or "pending").strip().lower() or "pending",
                "pickup_status": str(
                    status_row.get("pickup_status")
                    or row.get("pickup_status")
                    or "pending"
                ).strip().lower() or "pending",
                "updatedAt": status_row.get("updatedAt") or row.get("createdAt"),
            }
        )
    return entries


def _queue_status_rank(status: str) -> int:
    normalized = str(status or "pending").strip().lower()
    if normalized == "pending":
        return 0
    if normalized == "ready":
        return 1
    if normalized == "collected":
        return 2
    return 3


def _queue_sort_timestamp(row: Dict[str, Any]) -> float:
    parsed = _parse_iso_datetime(row.get("createdAt") or row.get("date") or "")
    if parsed is None:
        return 0
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).timestamp()


def _build_canteen_order_queue() -> Dict[str, Any]:
    queue_entries = _build_student_queue_entries() + _build_faculty_queue_entries()
    queue_entries.sort(
        key=lambda row: (
            _queue_status_rank(str(row.get("pickup_status") or "pending")),
            -_queue_sort_timestamp(row),
        )
    )
    pending_count = sum(1 for row in queue_entries if row.get("pickup_status") == "pending")
    ready_count = sum(1 for row in queue_entries if row.get("pickup_status") == "ready")
    collected_count = sum(1 for row in queue_entries if row.get("pickup_status") == "collected")
    return {
        "orders": queue_entries,
        "summary": {
            "total_orders": len(queue_entries),
            "pending_count": pending_count,
            "ready_count": ready_count,
            "collected_count": collected_count,
            "student_count": sum(1 for row in queue_entries if row.get("source") == "student"),
            "faculty_count": sum(1 for row in queue_entries if row.get("source") == "faculty"),
        },
    }


@app.get("/canteen/order-queue")
def get_canteen_order_queue(authorization: Optional[str] = Header(default=None)):
    _resolve_canteen_request(authorization)
    return _cached_response(
        "canteen:order_queue",
        FACULTY_CACHE_TTL_SECONDS,
        _build_canteen_order_queue,
    )


@app.post("/canteen/order-queue/status")
def update_canteen_order_queue_status(
    payload: PickupQueueStatusRequest,
    authorization: Optional[str] = Header(default=None),
):
    _resolve_canteen_request(authorization)
    source = str(payload.source or "").strip().lower()
    if source not in {"student", "faculty"}:
        raise HTTPException(status_code=400, detail="Invalid order source")
    pickup_status = str(payload.pickup_status or "").strip().lower()
    if pickup_status not in {"pending", "ready", "collected"}:
        raise HTTPException(status_code=400, detail="Invalid pickup status")

    order_token = str(payload.order_token or "").strip()
    order_id = str(payload.order_id or "").strip()
    identifier = order_id or order_token
    if not identifier:
        raise HTTPException(status_code=400, detail="Order token or order id is required")

    updated = 0
    if source == "student":
        orders = load_data(ORDERS_FILE, DEFAULT_ORDERS)
        for row in orders:
            row_batch_id = str(row.get("batch_id") or "").strip()
            row_token = str(row.get("order_token") or "").strip()
            row_id = str(row.get("id") or "").strip()
            if identifier not in {row_batch_id, row_token, row_id}:
                continue
            row["pickup_status"] = pickup_status
            updated += 1
        save_data(ORDERS_FILE, orders)
    else:
        faculty_orders = _load_faculty_orders_local()
        for row in faculty_orders:
            row_order_id = str(row.get("order_id") or "").strip()
            row_token = str(row.get("order_token") or "").strip()
            if identifier not in {row_order_id, row_token}:
                continue
            row["pickup_status"] = pickup_status
            updated += 1
        _save_faculty_orders_local(faculty_orders)
        try:
            if order_id:
                db.collection("faculty_orders").document(order_id).set(
                    {
                        "pickup_status": pickup_status,
                        "updatedAt": datetime.now(timezone.utc).isoformat(),
                    },
                    merge=True,
                )
        except Exception:
            pass

    if updated <= 0:
        raise HTTPException(status_code=404, detail="Order not found")

    status_rows = _load_pickup_queue_statuses()
    entry_key = _pickup_entry_key(source, order_id, order_token or identifier)
    now_iso = datetime.now(timezone.utc).isoformat()
    next_rows = [row for row in status_rows if row.get("entry_key") != entry_key]
    next_rows.insert(
        0,
        {
            "entry_key": entry_key,
            "order_token": order_token,
            "order_id": order_id or identifier,
            "source": source,
            "pickup_status": pickup_status,
            "updatedAt": now_iso,
        },
    )
    _save_pickup_queue_statuses(next_rows)
    _invalidate_cache_prefix("canteen:order_queue")
    return {
        "message": "Pickup status updated",
        "updated_count": updated,
        "pickup_status": pickup_status,
    }


@app.post("/faculty/orders")
def create_faculty_order(payload: FacultyOrderRequest):
    if payload.quantity <= 0:
        raise HTTPException(status_code=400, detail="Quantity must be greater than zero")
    if payload.unit_price < 0:
        raise HTTPException(status_code=400, detail="Price cannot be negative")


    total_amount = payload.unit_price * payload.quantity
    now = datetime.now(timezone.utc)
    batch_id = _build_order_batch_id(payload.faculty_id, now)
    order_token = _build_order_token(batch_id, now)
    order_id = f"faculty-{int(now.timestamp())}-{payload.faculty_id[:6]}"
    order_row = {
        "order_id": order_id,
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
        "order_token": order_token,
        "order_batch_id": batch_id,
        "pickup_status": "pending",
    }
    local_orders = _load_faculty_orders_local()
    local_orders = [row for row in local_orders if row.get("order_id") != order_id]
    local_orders.insert(0, order_row)
    _save_faculty_orders_local(local_orders)

    try:
        doc_ref = db.collection("faculty_orders").document(order_id)
        doc_ref.set(order_row, merge=True)
    except Exception:
        pass

    _invalidate_cache_prefix(f"faculty:orders:{payload.faculty_id}:")
    _invalidate_cache_prefix(f"faculty:pending_summary:{payload.faculty_id}:")
    _invalidate_cache_prefix("canteen:order_queue")


    return {
        "message": "Faculty order created with pending payment",
        "order_id": order_id,
        "order_token": order_token,
        "total_amount": total_amount,
        "payment_status": "pending",
    }




@app.get("/faculty/orders/{faculty_id}")
def get_faculty_orders(faculty_id: str, status: str = "pending"):
    normalized_status = str(status or "pending").strip().lower()

    def build_payload():
        orders = _local_faculty_orders_for_user(faculty_id, normalized_status)
        total_pending = sum(
            _safe_int(row.get("total_amount"), 0)
            for row in orders
            if str(row.get("payment_status") or "").strip().lower() == "pending"
        )
        return {
            "faculty_id": faculty_id,
            "orders": orders,
            "total_pending": total_pending,
            "data_source": "local_cache",
        }

    return _cached_response(
        f"faculty:orders:{faculty_id}:{normalized_status}",
        FACULTY_CACHE_TTL_SECONDS,
        build_payload,
    )




@app.post("/faculty/orders/pay")
def pay_faculty_orders(payload: FacultyPayRequest):
    now = datetime.now(timezone.utc).isoformat()
    updated = 0
    target_ids = set(payload.order_ids)
    local_orders = _load_faculty_orders_local()
    for row in local_orders:
        order_id = str(row.get("order_id", "")).strip()
        if row.get("faculty_id") != payload.faculty_id:
            continue
        if row.get("payment_status") != "pending":
            continue
        if target_ids and order_id not in target_ids:
            continue
        row["payment_status"] = "paid"
        row["paidAt"] = now
        updated += 1
    _save_faculty_orders_local(local_orders)

    try:
        if payload.order_ids:
            refs = [db.collection("faculty_orders").document(order_id) for order_id in payload.order_ids]
        else:
            docs = db.collection("faculty_orders") \
                .where("faculty_id", "==", payload.faculty_id) \
                .where("payment_status", "==", "pending") \
                .stream(timeout=3)
            refs = [db.collection("faculty_orders").document(doc.id) for doc in docs]
        for ref in refs:
            snapshot = ref.get()
            if not snapshot.exists:
                continue
            data = snapshot.to_dict() or {}
            if data.get("faculty_id") != payload.faculty_id:
                continue
            ref.set({"payment_status": "paid", "paidAt": now}, merge=True)
    except Exception:
        pass

    _invalidate_cache_prefix(f"faculty:orders:{payload.faculty_id}:")
    _invalidate_cache_prefix(f"faculty:pending_summary:{payload.faculty_id}:")
    _invalidate_cache_prefix("canteen:order_queue")


    return {"message": "Faculty payment settled", "updated": updated}




@app.get("/faculty/pending-summary/{faculty_id}")
def faculty_pending_summary(faculty_id: str, period: str = "weekly"):
    days = _period_days(period)

    def build_payload():
        pending = _collect_faculty_pending_local(days)
        total = int(pending.get(faculty_id, {}).get("total", 0))
        return {
            "faculty_id": faculty_id,
            "period": period,
            "total_pending": total,
            "notification_message": f"You have ₹{total} pending canteen payment this {period}.",
            "data_source": "local_cache",
        }

    return _cached_response(
        f"faculty:pending_summary:{faculty_id}:{period}",
        FACULTY_CACHE_TTL_SECONDS,
        build_payload,
    )




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
    try:
        metrics = run_training_cycle(trigger="manual_admin")
        return {
            "message": "Model retrained successfully",
            "metrics": metrics,
            "status": get_training_status(),
        }
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Model retraining failed: {str(exc)}",
        ) from exc


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
