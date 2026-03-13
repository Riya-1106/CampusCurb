"""Student analytics utilities.

This module reads order documents from Firestore and produces
simple insights such as most popular food items and peak order time.

If the Firestore collection is empty or missing fields, the functions
return safe defaults.
"""

import os

from firebase_connect import db

import pandas as pd


def student_behavior(top_n: int = 5):
    """Return high-level student ordering behavior analytics.

    Args:
        top_n: Number of top items to return for most popular food and top students.

    Returns:
        dict: analytics containing most popular foods, peak order time, veg/non-veg split, top students, and total orders.
    """

    # First try using local dataset (if available); else fall back to Firestore.
    df = None
    dataset_path = "models/food_demand_dataset.csv"

    try:
        if os.path.exists(dataset_path):
            df = pd.read_csv(dataset_path)
    except Exception:
        df = None

    if df is None:
        try:
            orders_ref = db.collection("orders")
            docs = orders_ref.stream()
        except Exception as e:
            # Firestore may be unavailable / misconfigured
            return {
                "most_popular_food": {},
                "peak_order_time": None,
                "veg_preference": None,
                "top_students": {},
                "total_orders": 0,
                "error": str(e)
            }

        data = []
        for doc in docs:
            data.append(doc.to_dict())

        if data:
            df = pd.DataFrame(data)

    # If we still have no data, return a strong sample analytic result
    if df is None or df.empty:
        return {
            "most_popular_food": {"Burger": 120},
            "peak_order_time": "1 PM",
            "veg_preference": "63%",
            "top_students": {"student_1": 23, "student_2": 18, "student_3": 14},
            "total_orders": 200,
            "note": "No order history available; returning sample analytics."
        }

    # Core analytics
    most_popular_food = {}
    peak_order_time = None
    veg_pref = None
    top_students = {}

    if "food_item" in df.columns and not df["food_item"].isna().all():
        most_popular_food = df["food_item"].value_counts().head(top_n).to_dict()

    if "time_slot" in df.columns and not df["time_slot"].isna().all():
        peak_order_time = df["time_slot"].value_counts().idxmax()

    # Veg vs Non-Veg preference
    if "is_veg" in df.columns and not df["is_veg"].isna().all():
        total = len(df)
        veg_count = int(df["is_veg"].astype(int).sum())
        veg_pref = f"{round((veg_count / total) * 100)}%"

    # Top students (if available)
    student_cols = [c for c in ["student_id", "student_name", "student"] if c in df.columns]
    if student_cols:
        student_col = student_cols[0]
        top_students = df[student_col].value_counts().head(top_n).to_dict()

    return {
        "most_popular_food": most_popular_food,
        "peak_order_time": peak_order_time,
        "veg_preference": veg_pref,
        "top_students": top_students,
        "total_orders": len(df)
    }
