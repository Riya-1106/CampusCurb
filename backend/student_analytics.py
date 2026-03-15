"""Analytics utilities for student behavior and prediction accuracy."""

import json
import os
from pathlib import Path

import pandas as pd

from firebase_connect import db


BASE_DIR = Path(__file__).resolve().parent
ORDERS_FILE = BASE_DIR / "data" / "orders.json"
DATASET_FILE = BASE_DIR / "models" / "food_demand_dataset.csv"


def _safe_read_dataset() -> pd.DataFrame:
    if not DATASET_FILE.exists():
        return pd.DataFrame()
    try:
        return pd.read_csv(DATASET_FILE)
    except Exception:
        return pd.DataFrame()


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
    if "item" in df.columns and "food_item" not in df.columns:
        df["food_item"] = df["item"]
    if "uid" in df.columns and "student_id" not in df.columns:
        df["student_id"] = df["uid"]
    if "time" in df.columns and "time_slot" not in df.columns:
        parsed = pd.to_datetime(df["time"], errors="coerce")
        hours = parsed.dt.hour
        df["time_slot"] = hours.apply(_hour_to_slot)
    return df


def _safe_read_firestore(collection_name: str) -> pd.DataFrame:
    try:
        docs = db.collection(collection_name).stream()
        rows = [doc.to_dict() for doc in docs]
    except Exception:
        return pd.DataFrame()
    return pd.DataFrame(rows) if rows else pd.DataFrame()


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


def _build_veg_ratio(order_df: pd.DataFrame, dataset_df: pd.DataFrame) -> dict:
    analysis_df = pd.DataFrame()

    if _has_series(order_df, "is_veg"):
        analysis_df = order_df[["is_veg"]].copy()
    elif _has_series(order_df, "food_item") and _has_series(dataset_df, "food_item") and _has_series(dataset_df, "is_veg"):
        inferred = dataset_df[["food_item", "is_veg"]].dropna().copy()
        if not inferred.empty:
            inferred["is_veg"] = pd.to_numeric(inferred["is_veg"], errors="coerce")
            inferred = inferred.dropna(subset=["is_veg"])
            mapping = inferred.groupby("food_item")["is_veg"].agg(lambda values: int(round(values.mean()))).to_dict()
            analysis_df = order_df[["food_item"]].copy()
            analysis_df["is_veg"] = analysis_df["food_item"].map(mapping)
    elif _has_series(dataset_df, "is_veg"):
        analysis_df = dataset_df[["is_veg"]].copy()

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
    """Return student ordering analytics using existing order and dataset data."""

    order_df = _safe_read_firestore("orders")
    if order_df.empty:
        order_df = _safe_read_local_orders()

    dataset_df = _safe_read_dataset()
    base_food_df = order_df if _has_series(order_df, "food_item") else dataset_df
    base_time_df = order_df if _has_series(order_df, "time_slot") else dataset_df

    if base_food_df.empty and dataset_df.empty and order_df.empty:
        return {
            "most_popular_food": {"Burger": 120},
            "most_ordered_food": {"name": "Burger", "orders": 120},
            "food_rankings": [
                {"name": "Burger", "count": 120},
                {"name": "Sandwich", "count": 94},
                {"name": "Pasta", "count": 82},
            ],
            "peak_order_time": "11:00-13:00",
            "peak_order_time_details": {"slot": "11:00-13:00", "orders": 88},
            "veg_preference": "63%",
            "veg_vs_non_veg_ratio": {
                "veg_count": 126,
                "non_veg_count": 74,
                "veg_percentage": 63.0,
                "non_veg_percentage": 37.0,
                "display": "63.0% veg / 37.0% non-veg",
            },
            "top_students": {"student_1": 23, "student_2": 18, "student_3": 14},
            "top_students_list": [
                {"student": "student_1", "orders": 23},
                {"student": "student_2", "orders": 18},
                {"student": "student_3", "orders": 14},
            ],
            "total_orders": 200,
            "note": "No order history available; returning sample analytics.",
        }

    most_popular_food, food_rankings = _top_counts(base_food_df, "food_item", top_n)
    top_students, top_students_list = _top_counts(order_df, "student_id", top_n)

    peak_order_time = None
    peak_order_time_details = {"slot": None, "orders": 0}
    if _has_series(base_time_df, "time_slot"):
        slot_counts = base_time_df["time_slot"].astype(str).value_counts()
        peak_order_time = str(slot_counts.idxmax())
        peak_order_time_details = {
            "slot": peak_order_time,
            "orders": int(slot_counts.iloc[0]),
        }

    veg_ratio = _build_veg_ratio(order_df, dataset_df)
    most_ordered_food = food_rankings[0] if food_rankings else {"name": "N/A", "orders": 0}

    return {
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
        "total_orders": int(len(order_df)) if not order_df.empty else int(len(base_food_df)),
    }


def prediction_accuracy_summary(top_n: int = 5):
    """Return prediction accuracy metrics using prediction_logs."""

    df = _safe_read_firestore("prediction_logs")
    if df.empty:
        return {
            "overall_accuracy_percentage": 95.0,
            "total_predictions": 1,
            "recent_logs": [
                {
                    "food_item": "Burger",
                    "predicted_demand": 120,
                    "actual_sold": 115,
                    "accuracy_percentage": 95.0,
                }
            ],
            "accuracy_by_food": [
                {
                    "food_item": "Burger",
                    "predicted_average": 120,
                    "actual_average": 115,
                    "accuracy_percentage": 95.0,
                }
            ],
            "note": "No prediction logs available; returning sample accuracy.",
        }

    required_cols = {"food_item", "predicted_demand", "actual_sold"}
    if not required_cols.issubset(df.columns):
        return {
            "overall_accuracy_percentage": 0.0,
            "total_predictions": 0,
            "recent_logs": [],
            "accuracy_by_food": [],
            "error": "prediction_logs is missing required fields.",
        }

    df = df.copy()
    df["predicted_demand"] = pd.to_numeric(df["predicted_demand"], errors="coerce")
    df["actual_sold"] = pd.to_numeric(df["actual_sold"], errors="coerce")
    df = df.dropna(subset=["predicted_demand", "actual_sold", "food_item"])
    if df.empty:
        return {
            "overall_accuracy_percentage": 0.0,
            "total_predictions": 0,
            "recent_logs": [],
            "accuracy_by_food": [],
        }

    denominator = df[["predicted_demand", "actual_sold"]].max(axis=1).clip(lower=1)
    df["accuracy_percentage"] = (1 - (df["predicted_demand"] - df["actual_sold"]).abs() / denominator) * 100
    df["accuracy_percentage"] = df["accuracy_percentage"].clip(lower=0).round(2)

    sort_column = "date" if "date" in df.columns else None
    recent_df = df.sort_values(by=sort_column, ascending=False) if sort_column else df.copy()
    recent_logs = []
    for _, row in recent_df.head(top_n).iterrows():
        recent_logs.append(
            {
                "food_item": str(row["food_item"]),
                "predicted_demand": int(row["predicted_demand"]),
                "actual_sold": int(row["actual_sold"]),
                "accuracy_percentage": float(row["accuracy_percentage"]),
            }
        )

    grouped = (
        df.groupby("food_item", dropna=True)
        .agg(
            predicted_average=("predicted_demand", "mean"),
            actual_average=("actual_sold", "mean"),
            accuracy_percentage=("accuracy_percentage", "mean"),
        )
        .sort_values(by="accuracy_percentage", ascending=False)
        .head(top_n)
        .reset_index()
    )
    accuracy_by_food = []
    for _, row in grouped.iterrows():
        accuracy_by_food.append(
            {
                "food_item": str(row["food_item"]),
                "predicted_average": round(float(row["predicted_average"]), 2),
                "actual_average": round(float(row["actual_average"]), 2),
                "accuracy_percentage": round(float(row["accuracy_percentage"]), 2),
            }
        )

    return {
        "overall_accuracy_percentage": round(float(df["accuracy_percentage"].mean()), 2),
        "total_predictions": int(len(df)),
        "recent_logs": recent_logs,
        "accuracy_by_food": accuracy_by_food,
    }
