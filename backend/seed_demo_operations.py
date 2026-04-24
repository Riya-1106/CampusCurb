#!/usr/bin/env python3
"""Seed realistic historical canteen operations for demos.

This is useful when there is not enough time to collect weeks of live canteen
data before a presentation. The generated rows are clearly marked as demo seed
records and can be regenerated safely.
"""

from __future__ import annotations

import json
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
MENU_PATH = DATA_DIR / "menu.json"
OPERATIONS_PATH = DATA_DIR / "canteen_operations.json"

TIME_SLOTS = ["09:00-11:00", "11:00-13:00", "13:00-15:00", "15:00+"]
DEMO_PREFIX = "demo-seed"

ITEM_BASE_DEMAND = {
    "veg wrap": 58,
    "masala dosa": 72,
    "cheese pizza": 54,
    "idli": 68,
    "coffee": 96,
    "tea": 112,
    "milk": 76,
    "sandwich": 84,
    "noodles": 78,
    "burger": 82,
    "pasta": 70,
    "coke diet": 44,
}

CATEGORY_MULTIPLIER = {
    "breakfast": 1.10,
    "beverage": 1.05,
    "fastfood": 1.00,
    "meal": 0.95,
    "snack": 0.90,
    "general": 0.85,
}

SLOT_MULTIPLIER = {
    "09:00-11:00": 0.78,
    "11:00-13:00": 1.16,
    "13:00-15:00": 1.08,
    "15:00+": 0.72,
}

WEATHER_OPTIONS = [
    ("Sunny", 31, 1.00),
    ("Cloudy", 28, 0.97),
    ("Rainy", 25, 0.88),
    ("Hot", 34, 1.04),
]


def _read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text())
    except Exception:
        return default


def _write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2))


def _slug(value: str) -> str:
    return value.strip().lower().replace(" ", "-")


def _is_veg(name: str) -> int:
    lowered = name.lower()
    return 0 if any(token in lowered for token in ["chicken", "egg", "fish", "mutton"]) else 1


def _portion_size(category: str) -> float:
    return {
        "beverage": 1.0,
        "breakfast": 1.2,
        "fastfood": 1.4,
        "meal": 1.8,
        "snack": 1.1,
    }.get(category, 1.3)


def _confidence_label(score: float) -> str:
    if score >= 76:
        return "High"
    if score >= 50:
        return "Medium"
    return "Low"


def generate_seed_rows(days: int = 28) -> list[dict[str, Any]]:
    menu_rows = _read_json(MENU_PATH, [])
    if not menu_rows:
        raise RuntimeError("No active menu rows found. Add menu.json before seeding.")

    rng = random.Random(42)
    today = datetime.now().date()
    rows: list[dict[str, Any]] = []

    for days_back in range(days, 0, -1):
        service_date = today - timedelta(days=days_back)
        weekday = service_date.weekday()
        weekend_multiplier = 0.72 if weekday >= 5 else 1.0
        exam_multiplier = 1.12 if weekday in {1, 2} and days_back % 9 in {0, 1} else 1.0
        holiday_flag = 1 if weekday == 6 and days_back % 3 == 0 else 0
        holiday_multiplier = 0.62 if holiday_flag else 1.0
        weather, temperature, weather_multiplier = WEATHER_OPTIONS[days_back % len(WEATHER_OPTIONS)]

        for slot in TIME_SLOTS:
            slot_multiplier = SLOT_MULTIPLIER[slot]
            for index, item in enumerate(menu_rows):
                name = str(item.get("name", "")).strip()
                if not name:
                    continue
                category = str(item.get("category") or "general").strip().lower() or "general"
                price = int(item.get("price") or 0)
                base = ITEM_BASE_DEMAND.get(name.lower(), 55)
                category_multiplier = CATEGORY_MULTIPLIER.get(category, 0.9)
                weekly_wave = 1 + (((days_back + index) % 7) - 3) * 0.035
                noise = rng.uniform(0.90, 1.11)

                sold = round(
                    base
                    * category_multiplier
                    * slot_multiplier
                    * weekend_multiplier
                    * exam_multiplier
                    * holiday_multiplier
                    * weather_multiplier
                    * weekly_wave
                    * noise
                )
                sold = max(3, sold)

                waste_rate = 0.05 + (0.04 if category in {"meal", "fastfood"} else 0.02)
                if weather == "Rainy":
                    waste_rate += 0.03
                prepared = max(sold, round(sold * (1.08 + waste_rate + rng.uniform(-0.02, 0.04))))
                wasted = max(prepared - sold, 0)
                predicted = max(1, round(sold * rng.uniform(0.92, 1.08)))
                suggested = max(predicted, round(predicted * (1.08 + waste_rate)))
                confidence = round(rng.uniform(66, 88), 2)

                rows.append(
                    {
                        "id": f"{DEMO_PREFIX}|{service_date.isoformat()}|{slot}|{_slug(name)}",
                        "date": service_date.isoformat(),
                        "time_slot": slot,
                        "food_item": name,
                        "food_category": category,
                        "price": price,
                        "predicted_demand": predicted,
                        "suggested_preparation": suggested,
                        "quantity_prepared": prepared,
                        "quantity_sold": sold,
                        "quantity_wasted": wasted,
                        "confidence_score": confidence,
                        "confidence_label": _confidence_label(confidence),
                        "weather_type": weather,
                        "temperature": temperature,
                        "is_holiday": holiday_flag,
                        "is_exam_day": 1 if exam_multiplier > 1 else 0,
                        "is_veg": _is_veg(name),
                        "portion_size": _portion_size(category),
                        "is_special_item": 1 if (days_back + index) % 11 == 0 else 0,
                        "max_capacity": 320,
                        "staff_count": 6 if slot in {"11:00-13:00", "13:00-15:00"} else 4,
                        "notes": "Demo historical operation seed",
                        "recorded_by": DEMO_PREFIX,
                        "college_key": "demo-college",
                        "updated_at": datetime.now(timezone.utc).isoformat(),
                    }
                )

    return rows


def main() -> None:
    existing_rows = _read_json(OPERATIONS_PATH, [])
    if not isinstance(existing_rows, list):
        existing_rows = []
    real_rows = [
        row
        for row in existing_rows
        if not str(row.get("id", "")).startswith(f"{DEMO_PREFIX}|")
    ]
    seed_rows = generate_seed_rows()
    _write_json(OPERATIONS_PATH, [*real_rows, *seed_rows])
    print(
        f"Seeded {len(seed_rows)} demo operation rows and preserved {len(real_rows)} existing rows."
    )


if __name__ == "__main__":
    main()
