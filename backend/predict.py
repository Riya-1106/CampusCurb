from __future__ import annotations

from datetime import datetime
from typing import Any

from ml_pipeline import (
    _latest_demand_dashboard_snapshot,
    _safe_read_operations,
    build_demand_dashboard,
    build_ml_system_overview,
    generate_forecast_rows,
    get_forecast_menu_items,
    predict_live_demand,
)


def _fast_demand_dashboard_fallback(
    *,
    target_date: str | None = None,
    time_slot: str | None = None,
) -> dict[str, Any]:
    slot = str(time_slot or "11:00-13:00").strip() or "11:00-13:00"
    if target_date:
        try:
            target_datetime = datetime.fromisoformat(target_date)
        except ValueError:
            target_datetime = datetime.strptime(target_date, "%Y-%m-%d")
    else:
        target_datetime = datetime.now()
    target_date_key = target_datetime.strftime("%Y-%m-%d")

    operations_df = _safe_read_operations()
    menu_rows = get_forecast_menu_items()
    dashboard_rows: list[dict[str, Any]] = []

    for item in menu_rows:
        item_name = str(item.get("name", "")).strip()
        if not item_name:
            continue

        matching_rows = operations_df[
            operations_df["food_item"].astype(str).str.strip().str.lower()
            == item_name.lower()
        ] if not operations_df.empty and "food_item" in operations_df.columns else operations_df.iloc[0:0]
        if not matching_rows.empty and "time_slot" in matching_rows.columns:
            slot_rows = matching_rows[
                matching_rows["time_slot"].astype(str).str.strip() == slot
            ]
            if not slot_rows.empty:
                matching_rows = slot_rows

        average_sold = 0.0
        average_prepared = 0.0
        if not matching_rows.empty:
            if "quantity_sold" in matching_rows.columns:
                average_sold = float(matching_rows["quantity_sold"].fillna(0).mean())
            if "quantity_prepared" in matching_rows.columns:
                average_prepared = float(matching_rows["quantity_prepared"].fillna(0).mean())

        predicted_demand = int(round(average_sold))
        suggested_preparation = int(round(max(average_prepared, average_sold)))
        expected_waste = max(suggested_preparation - predicted_demand, 0)
        confidence_score = 55.0 if not matching_rows.empty else 20.0
        confidence_label = "Medium" if not matching_rows.empty else "Low"

        dashboard_rows.append(
            {
                "food_item": item_name,
                "food_category": str(item.get("category") or "general").strip().lower() or "general",
                "predicted_demand": predicted_demand,
                "model_predicted_demand": predicted_demand,
                "suggested_preparation": suggested_preparation,
                "expected_waste": expected_waste,
                "expected_demand_anchor": round(average_sold, 2),
                "recommended_buffer_percentage": 0.0,
                "expected_sell_through_percentage": round(
                    (predicted_demand / suggested_preparation * 100.0)
                    if suggested_preparation
                    else 0.0,
                    2,
                ),
                "historical_average_sales": round(average_sold, 2),
                "recent_average_sales": round(average_sold, 2),
                "historical_preparation_average": int(round(average_prepared)),
                "historical_waste_average": round(max(average_prepared - average_sold, 0.0), 2),
                "confidence_score": confidence_score,
                "confidence_label": confidence_label,
                "confidence_reason": (
                    "Built from recent canteen operations."
                    if not matching_rows.empty
                    else "Waiting for more live canteen operations for this item."
                ),
                "trend_direction": "stable",
                "trend_reason": "Using fast local fallback until a fresh live forecast is generated.",
                "recommended_action": (
                    "Keep preparation steady"
                    if suggested_preparation > 0
                    else "Collect more live service logs"
                ),
                "time_slot": slot,
                "target_date": target_date_key,
                "weather_type": "Sunny",
                "temperature": 29,
                "model_name": "Fast local fallback",
                "feature_snapshot": {
                    "fallback": True,
                    "live_operation_rows": int(len(matching_rows)),
                },
            }
        )

    dashboard_rows.sort(key=lambda row: row["predicted_demand"], reverse=True)
    total_predicted = sum(int(row.get("predicted_demand", 0) or 0) for row in dashboard_rows)
    total_preparation = sum(int(row.get("suggested_preparation", 0) or 0) for row in dashboard_rows)
    low_confidence_items = [
        row.get("food_item", "Unknown")
        for row in dashboard_rows
        if str(row.get("confidence_label", "")).strip().lower() == "low"
    ]
    average_confidence = round(
        sum(float(row.get("confidence_score", 0) or 0) for row in dashboard_rows) / len(dashboard_rows),
        2,
    ) if dashboard_rows else 0.0

    return {
        "dashboard": dashboard_rows,
        "summary": {
            "items_forecasted": len(dashboard_rows),
            "active_menu_items": len(menu_rows),
            "total_predicted_demand": total_predicted,
            "total_suggested_preparation": total_preparation,
            "estimated_total_waste": max(total_preparation - total_predicted, 0),
            "average_confidence": average_confidence,
            "highest_demand_item": dashboard_rows[0]["food_item"] if dashboard_rows else "N/A",
            "low_confidence_count": len(low_confidence_items),
            "target_date": target_date_key,
            "generated_at": datetime.now().isoformat(),
            "time_slot": slot,
            "fallback_mode": True,
        },
        "low_confidence_items": low_confidence_items,
        "menu_basis": {
            "source": "active_menu",
            "items": menu_rows,
        },
        "formula": (
            "Showing a fast local forecast built from recent canteen operations and active menu items "
            "until a fresh full ML forecast is generated."
        ),
        "example": "This keeps the dashboard responsive even before a new live forecast run finishes.",
        "model": {
            "name": "Fast local fallback",
            "trained_at": None,
        },
    }


def predict_demand(input_data: dict[str, Any]) -> dict[str, Any]:
    return predict_live_demand(input_data, log_request=True, source="predict_endpoint")


def demand_dashboard_data(
    *,
    target_date: str | None = None,
    time_slot: str | None = None,
) -> dict[str, Any]:
    snapshot = _latest_demand_dashboard_snapshot()
    snapshot_summary = snapshot.get("summary", {})
    snapshot_date = str(snapshot_summary.get("target_date") or "").strip()
    snapshot_slot = str(snapshot_summary.get("time_slot") or "").strip()
    requested_date = str(target_date or "").strip()
    requested_slot = str(time_slot or "").strip()
    snapshot_has_rows = bool(snapshot.get("dashboard"))

    if snapshot_has_rows:
        date_matches = not requested_date or requested_date == snapshot_date
        slot_matches = not requested_slot or requested_slot == snapshot_slot
        if date_matches and slot_matches:
            return snapshot

        latest_snapshot = dict(snapshot)
        latest_summary = dict(snapshot_summary)
        if requested_date:
            latest_summary["requested_target_date"] = requested_date
        if requested_slot:
            latest_summary["requested_time_slot"] = requested_slot
        latest_snapshot["summary"] = latest_summary
        latest_snapshot["formula"] = (
            "Showing the latest cached forecast snapshot for speed. "
            "Generate a fresh forecast from operations when needed."
        )
        return latest_snapshot
    return _fast_demand_dashboard_fallback(
        target_date=target_date,
        time_slot=time_slot,
    )


def menu_optimization() -> dict[str, Any]:
    dashboard = build_demand_dashboard(log_request=False)
    suggestions = []
    for item in dashboard.get("dashboard", []):
        predicted = int(item.get("predicted_demand", 0))
        suggested = int(item.get("suggested_preparation", 0))
        recent_average = float(item.get("recent_average_sales", 0))
        if predicted >= recent_average * 1.1:
            action = "Increase preparation"
            reason = item.get("trend_reason") or "Demand is trending above the recent average."
        elif predicted <= recent_average * 0.9:
            action = "Reduce preparation"
            reason = item.get("trend_reason") or "Demand is trending below the recent average."
        else:
            action = "Keep preparation steady"
            reason = item.get("recommended_action") or "Demand is stable."

        suggestions.append(
            {
                "food_item": item.get("food_item"),
                "current_average_sales": round(recent_average, 2),
                "current_average_preparation": item.get("historical_preparation_average", 0),
                "suggested_preparation": suggested,
                "predicted_demand": predicted,
                "confidence_label": item.get("confidence_label", "Medium"),
                "action": action,
                "reason": reason,
            }
        )

    high_demand = {
        item.get("food_item"): int(item.get("predicted_demand", 0))
        for item in dashboard.get("dashboard", [])[:3]
    }
    low_demand = {
        item.get("food_item"): int(item.get("predicted_demand", 0))
        for item in dashboard.get("dashboard", [])[-3:]
    }

    return {
        "high_demand_items": high_demand,
        "low_demand_items": low_demand,
        "optimization_suggestions": suggestions,
        "generated_at": datetime.now().isoformat(),
    }


def generate_forecast() -> list[dict[str, Any]]:
    return generate_forecast_rows(days_ahead=1)


def get_ml_overview() -> dict[str, Any]:
    return build_ml_system_overview()


def get_rewards(points: int) -> str:
    if points >= 500:
        return "Free meal"
    if points >= 250:
        return "10% discount"
    if points >= 100:
        return "5% discount"
    return "No reward"


if __name__ == "__main__":
    sample = {
        "food_item": "Veg Wrap",
        "time_slot": "11:00-13:00",
        "weather_type": "Sunny",
        "price": 80,
        "temperature": 30,
    }
    print("Prediction:", predict_demand(sample))
    print("Demand dashboard:", demand_dashboard_data())
    print("ML overview:", get_ml_overview())
