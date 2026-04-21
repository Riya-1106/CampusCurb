from __future__ import annotations

from datetime import datetime
from typing import Any

from ml_pipeline import (
    build_demand_dashboard,
    build_ml_system_overview,
    generate_forecast_rows,
    predict_live_demand,
)


def predict_demand(input_data: dict[str, Any]) -> dict[str, Any]:
    return predict_live_demand(input_data, log_request=True, source="predict_endpoint")


def demand_dashboard_data() -> dict[str, Any]:
    return build_demand_dashboard(log_request=True)


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
