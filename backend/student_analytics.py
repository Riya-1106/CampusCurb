"""Student analytics utilities.

This module reads order documents from Firestore and produces
simple insights such as most popular food items and peak order time.

If the Firestore collection is empty or missing fields, the functions
return safe defaults.
"""

from firebase_connect import db

import pandas as pd


def student_behavior(top_n: int = 5):
    """Return high-level student ordering behavior analytics.

    Args:
        top_n: Number of top items to return for most popular food.

    Returns:
        dict: analytics containing most popular foods, peak order time, and total orders.
    """

    try:
        orders_ref = db.collection("orders")
        docs = orders_ref.stream()
    except Exception as e:
        # Firestore may be unavailable / misconfigured
        return {
            "most_popular_food": {},
            "peak_order_time": None,
            "total_orders": 0,
            "error": str(e)
        }

    data = []

    for doc in docs:
        data.append(doc.to_dict())

    if not data:
        return {
            "most_popular_food": {},
            "peak_order_time": None,
            "total_orders": 0
        }

    df = pd.DataFrame(data)

    # Safely compute counts only if columns exist
    popular_food = {}
    peak_time = None

    if "food_item" in df.columns and not df["food_item"].isna().all():
        popular_food = df["food_item"].value_counts().head(top_n).to_dict()

    if "time_slot" in df.columns and not df["time_slot"].isna().all():
        peak_time = df["time_slot"].value_counts().idxmax()

    return {
        "most_popular_food": popular_food,
        "peak_order_time": peak_time,
        "total_orders": len(df)
    }
