from __future__ import annotations

from datetime import datetime
import threading
from typing import Any

from firebase_connect import db
from ml_pipeline import PREDICTION_LOGS_PATH, _safe_read_json, _safe_write_json


def _log_id(food_item: str, target_date: str, time_slot: str, source: str) -> str:
    normalized_food = "".join(
        ch if ch.isalnum() else "-" for ch in food_item.strip().lower()
    ).strip("-")
    return f"{source}|{target_date}|{time_slot}|{normalized_food}"


def _sync_prediction_to_firestore(payload: dict[str, Any]) -> None:
    try:
        db.collection("prediction_logs").document(payload["id"]).set(payload, merge=True)
    except Exception:
        # Local logging is the durable fallback when Firestore is slow.
        pass


def _normalized_food_key(value: Any) -> str:
    return str(value or "").strip().lower()


def log_prediction(
    food_item: str,
    predicted_demand: int,
    suggested_preparation: int,
    actual_sold: int | None = None,
    *,
    target_date: str | None = None,
    time_slot: str | None = None,
    source: str = "prediction_request",
    historical_baseline_actual: int | None = None,
    historical_preparation_average: int | None = None,
    confidence_score: float | None = None,
    confidence_label: str | None = None,
    model_name: str | None = None,
    feature_snapshot: dict[str, Any] | None = None,
    expected_waste: int | None = None,
) -> None:
    now = datetime.now()
    target_date = target_date or now.strftime("%Y-%m-%d")
    time_slot = time_slot or "11:00-13:00"

    payload = {
        "id": _log_id(food_item, target_date, time_slot, source),
        "food_item": food_item,
        "predicted_demand": int(predicted_demand),
        "suggested_preparation": int(suggested_preparation),
        "actual_sold": int(actual_sold) if actual_sold is not None else None,
        "historical_baseline_actual": int(historical_baseline_actual)
        if historical_baseline_actual is not None
        else None,
        "historical_preparation_average": int(historical_preparation_average)
        if historical_preparation_average is not None
        else None,
        "prediction_error": (
            abs(int(predicted_demand) - int(actual_sold))
            if actual_sold is not None
            else None
        ),
        "target_date": target_date,
        "time_slot": time_slot,
        "source": source,
        "model_name": model_name,
        "confidence_score": confidence_score,
        "confidence_label": confidence_label,
        "feature_snapshot": feature_snapshot or {},
        "expected_waste": int(expected_waste) if expected_waste is not None else None,
        "logged_at": now.isoformat(),
        "date": target_date,
    }

    rows = _safe_read_json(PREDICTION_LOGS_PATH, [])
    if not isinstance(rows, list):
        rows = []

    replaced = False
    for index, row in enumerate(rows):
        if isinstance(row, dict) and row.get("id") == payload["id"]:
            rows[index] = payload
            replaced = True
            break
    if not replaced:
        rows.append(payload)
    _safe_write_json(PREDICTION_LOGS_PATH, rows)

    threading.Thread(
        target=_sync_prediction_to_firestore,
        args=(payload,),
        daemon=True,
    ).start()


def apply_operation_actuals(
    *,
    food_item: str,
    target_date: str,
    time_slot: str,
    actual_prepared: int | None = None,
    actual_sold: int | None = None,
    actual_wasted: int | None = None,
) -> int:
    rows = _safe_read_json(PREDICTION_LOGS_PATH, [])
    if not isinstance(rows, list) or not rows:
        return 0

    normalized_food = _normalized_food_key(food_item)
    updated_rows: list[dict[str, Any]] = []
    updated_count = 0

    for row in rows:
        if not isinstance(row, dict):
            continue

        matches = (
            str(row.get("target_date", "")).strip() == target_date
            and str(row.get("time_slot", "")).strip() == time_slot
            and _normalized_food_key(row.get("food_item")) == normalized_food
        )
        if matches:
            if actual_prepared is not None:
                row["actual_prepared"] = int(actual_prepared)
            if actual_sold is not None:
                row["actual_sold"] = int(actual_sold)
            if actual_wasted is not None:
                row["actual_wasted"] = int(actual_wasted)
            row["resolved_at"] = datetime.now().isoformat()
            updated_count += 1
            threading.Thread(
                target=_sync_prediction_to_firestore,
                args=(row.copy(),),
                daemon=True,
            ).start()
        updated_rows.append(row)

    if updated_count:
        _safe_write_json(PREDICTION_LOGS_PATH, updated_rows)
    return updated_count
