"""Analytics utilities for student behavior and prediction accuracy."""

import json
from pathlib import Path

import pandas as pd

from ml_pipeline import compute_prediction_accuracy_summary


BASE_DIR = Path(__file__).resolve().parent
ORDERS_FILE = BASE_DIR / "data" / "orders.json"
def _empty_student_analytics(note: str | None = None) -> dict:
    payload = {
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
        "data_sources": {
            "local_orders_used": False,
            "dataset_used": False,
        },
    }
    if note:
        payload["note"] = note
    return payload


def _safe_read_local_orders() -> pd.DataFrame:
    if not ORDERS_FILE.exists():
        return pd.DataFrame()
    try:
        rows = json.loads(ORDERS_FILE.read_text())
    except Exception:
        return pd.DataFrame()

    if not rows:
        return pd.DataFrame()

    df = pd.DataFrame(rows)
    return _normalize_order_frame(df)


def _normalize_order_frame(df: pd.DataFrame) -> pd.DataFrame:
    if df.empty:
        return df
    if "item" in df.columns and "food_item" not in df.columns:
        df["food_item"] = df["item"]
    if "uid" in df.columns and "student_id" not in df.columns:
        df["student_id"] = df["uid"]
    if "time" in df.columns and "time_slot" not in df.columns:
        parsed = pd.to_datetime(df["time"], errors="coerce")
        hours = parsed.dt.hour
        df["time_slot"] = hours.apply(_hour_to_slot)
    if "timestamp" in df.columns and "time_slot" not in df.columns:
        parsed = pd.to_datetime(df["timestamp"], errors="coerce")
        hours = parsed.dt.hour
        df["time_slot"] = hours.apply(_hour_to_slot)
    return df


def _hour_to_slot(hour):
    if pd.isna(hour):
        return None
    hour = int(hour)
    if hour < 11:
        return "09:00-11:00"
    if hour < 13:
        return "11:00-13:00"
    if hour < 15:
        return "13:00-15:00"
    return "15:00+"


def _has_series(df: pd.DataFrame, column: str) -> bool:
    return column in df.columns and not df[column].dropna().empty


def _top_counts(df: pd.DataFrame, column: str, top_n: int) -> tuple[dict, list]:
    if not _has_series(df, column):
        return {}, []
    counts = df[column].astype(str).value_counts().head(top_n)
    as_dict = {str(key): int(value) for key, value in counts.to_dict().items()}
    as_list = [{"name": str(key), "count": int(value)} for key, value in counts.items()]
    return as_dict, as_list


def _infer_is_veg_from_name(name: str) -> int:
    normalized = str(name or "").strip().lower()
    non_veg_tokens = ["chicken", "egg", "mutton", "fish", "meat"]
    return 0 if any(token in normalized for token in non_veg_tokens) else 1


def _build_veg_ratio(order_df: pd.DataFrame) -> dict:
    analysis_df = pd.DataFrame()

    if _has_series(order_df, "is_veg"):
        analysis_df = order_df[["is_veg"]].copy()
    elif _has_series(order_df, "food_item"):
        analysis_df = order_df[["food_item"]].copy()
        analysis_df["is_veg"] = analysis_df["food_item"].apply(_infer_is_veg_from_name)

    if analysis_df.empty or analysis_df["is_veg"].dropna().empty:
        return {
            "veg_count": 0,
            "non_veg_count": 0,
            "veg_percentage": 0.0,
            "non_veg_percentage": 0.0,
            "display": "N/A",
        }

    veg_values = pd.to_numeric(analysis_df["is_veg"], errors="coerce").dropna().astype(int)
    total = int(len(veg_values))
    veg_count = int((veg_values == 1).sum())
    non_veg_count = int((veg_values == 0).sum())
    veg_percentage = round((veg_count / total) * 100, 2) if total else 0.0
    non_veg_percentage = round((non_veg_count / total) * 100, 2) if total else 0.0

    return {
        "veg_count": veg_count,
        "non_veg_count": non_veg_count,
        "veg_percentage": veg_percentage,
        "non_veg_percentage": non_veg_percentage,
        "display": f"{veg_percentage}% veg / {non_veg_percentage}% non-veg",
    }


def student_behavior(top_n: int = 5):
    """Return student ordering analytics using live order history only."""
    try:
        order_df = _safe_read_local_orders()
        if order_df.empty:
            return _empty_student_analytics(
                "No live order history is available yet. Student analytics will appear after students start placing orders."
            )

        most_popular_food, food_rankings = _top_counts(order_df, "food_item", top_n)
        top_students, top_students_list = _top_counts(order_df, "student_id", top_n)

        peak_order_time = None
        peak_order_time_details = {"slot": None, "orders": 0}
        if _has_series(order_df, "time_slot"):
            slot_counts = order_df["time_slot"].astype(str).value_counts()
            peak_order_time = str(slot_counts.idxmax())
            peak_order_time_details = {
                "slot": peak_order_time,
                "orders": int(slot_counts.iloc[0]),
            }

        veg_ratio = _build_veg_ratio(order_df)
        most_ordered_food = food_rankings[0] if food_rankings else {"name": "N/A", "orders": 0}

        payload = _empty_student_analytics()
        payload.update(
            {
                "most_popular_food": most_popular_food,
                "most_ordered_food": {
                    "name": most_ordered_food.get("name", "N/A"),
                    "orders": int(most_ordered_food.get("count", 0)),
                },
                "food_rankings": food_rankings,
                "peak_order_time": peak_order_time,
                "peak_order_time_details": peak_order_time_details,
                "veg_preference": f"{veg_ratio['veg_percentage']}%",
                "veg_vs_non_veg_ratio": veg_ratio,
                "top_students": top_students,
                "top_students_list": [
                    {"student": item["name"], "orders": item["count"]}
                    for item in top_students_list
                ],
                "total_orders": int(len(order_df)),
                "data_sources": {
                    "local_orders_used": not order_df.empty,
                    "dataset_used": False,
                },
            }
        )
        return payload
    except Exception as exc:
        return _empty_student_analytics(
            f"Student analytics is temporarily using a safe fallback because live analytics could not be fully processed: {str(exc)}"
        )


def prediction_accuracy_summary(top_n: int = 5):
    """Return prediction accuracy metrics using resolved prediction logs."""

    return compute_prediction_accuracy_summary(top_n=top_n)
