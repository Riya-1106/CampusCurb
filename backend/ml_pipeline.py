from __future__ import annotations

import json
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import GradientBoostingRegressor, RandomForestRegressor
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
MODELS_DIR = BASE_DIR / "models"

DATASET_PATH = MODELS_DIR / "food_demand_dataset.csv"
ORDERS_PATH = DATA_DIR / "orders.json"
MENU_PATH = DATA_DIR / "menu.json"
ATTENDANCE_PATH = DATA_DIR / "attendance.json"
OPERATIONS_PATH = DATA_DIR / "canteen_operations.json"
PREDICTION_LOGS_PATH = DATA_DIR / "prediction_logs.json"
TRAINING_METRICS_PATH = DATA_DIR / "ml_training_metrics.json"
TRAINING_STATUS_PATH = DATA_DIR / "ml_training_status.json"
TRAINING_HISTORY_PATH = DATA_DIR / "ml_training_history.json"
MODEL_BUNDLE_PATH = MODELS_DIR / "model_bundle.pkl"
BEST_MODEL_PATH = MODELS_DIR / "best_model.pkl"
FORECAST_OUTPUT_PATH = DATA_DIR / "tomorrow_forecast.csv"

FEATURE_COLUMNS = [
    "day_of_week",
    "week_of_year",
    "month",
    "time_slot",
    "is_weekend",
    "is_holiday",
    "is_exam_day",
    "food_item",
    "food_category",
    "is_veg",
    "price",
    "portion_size",
    "is_special_item",
    "prev_day_sales",
    "prev_same_slot_sales",
    "prev_week_same_day_slot_sales",
    "avg_last_3_days_sales",
    "avg_last_7_days_sales",
    "sales_trend_3_days",
    "sales_trend_weekly",
    "demand_variance",
    "quantity_prepared",
    "quantity_wasted",
    "leftover_percentage",
    "max_capacity",
    "staff_count",
    "weather_type",
    "temperature",
]

TARGET_COLUMN = "quantity_sold"

CATEGORICAL_FEATURES = [
    "time_slot",
    "food_item",
    "food_category",
    "weather_type",
]

NUMERIC_FEATURES = [
    column for column in FEATURE_COLUMNS if column not in CATEGORICAL_FEATURES
]

DEFAULT_ROW = {
    "day_of_week": 2,
    "week_of_year": 10,
    "month": 3,
    "time_slot": "11:00-13:00",
    "is_weekend": 0,
    "is_holiday": 0,
    "is_exam_day": 0,
    "food_item": "Veg Wrap",
    "food_category": "general",
    "is_veg": 1,
    "price": 80,
    "portion_size": 1.5,
    "is_special_item": 0,
    "prev_day_sales": 60,
    "prev_same_slot_sales": 65,
    "prev_week_same_day_slot_sales": 58,
    "avg_last_3_days_sales": 62,
    "avg_last_7_days_sales": 64,
    "sales_trend_3_days": 3,
    "sales_trend_weekly": 4,
    "demand_variance": 9,
    "quantity_prepared": 80,
    "quantity_wasted": 8,
    "leftover_percentage": 10,
    "max_capacity": 300,
    "staff_count": 6,
    "weather_type": "Sunny",
    "temperature": 29,
}

DEFAULT_MENU_ITEMS = [
    {"name": "Veg Wrap", "price": 80, "category": "snack"},
    {"name": "Masala Dosa", "price": 50, "category": "breakfast"},
    {"name": "Cheese Pizza", "price": 120, "category": "meal"},
]

TIME_SLOTS = ["09:00-11:00", "11:00-13:00", "13:00-15:00", "15:00+"]


def _safe_read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text())
    except Exception:
        return default


def _safe_write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2))


def _snapshot_training_metrics(metrics: dict[str, Any] | None = None) -> dict[str, Any]:
    metrics = get_training_metrics() if metrics is None else metrics
    return {
        "best_model_name": metrics.get("best_model_name", "Not trained"),
        "trained_at": metrics.get("trained_at"),
        "dataset_rows": int(metrics.get("dataset_rows", 0) or 0),
        "live_rows_added": int(metrics.get("live_rows_added", 0) or 0),
        "train_rows": int(metrics.get("train_rows", 0) or 0),
        "test_rows": int(metrics.get("test_rows", 0) or 0),
        "best_r2": round(float(metrics.get("best_r2", 0.0) or 0.0), 4),
    }


def _append_training_history(entry: dict[str, Any], limit: int = 8) -> None:
    history = _safe_read_json(TRAINING_HISTORY_PATH, [])
    if not isinstance(history, list):
        history = []
    history.insert(0, entry)
    _safe_write_json(TRAINING_HISTORY_PATH, history[:limit])


def get_training_status() -> dict[str, Any]:
    metrics_snapshot = _snapshot_training_metrics()
    trained_at = metrics_snapshot.get("trained_at")
    default_status = {
        "status": "success" if trained_at else "not_started",
        "last_started_at": trained_at,
        "last_completed_at": trained_at,
        "last_trigger": "legacy" if trained_at else None,
        "last_error": None,
        "last_duration_seconds": None,
    }

    saved_status = _safe_read_json(TRAINING_STATUS_PATH, {})
    if not isinstance(saved_status, dict):
        saved_status = {}
    history = _safe_read_json(TRAINING_HISTORY_PATH, [])
    if not isinstance(history, list):
        history = []

    status = {
        **default_status,
        **saved_status,
        **metrics_snapshot,
        "recent_runs": history[:5],
    }
    status["status_label"] = {
        "running": "Training in progress",
        "success": "Healthy",
        "failed": "Needs attention",
        "not_started": "Not started",
    }.get(str(status.get("status") or "").lower(), "Unknown")
    return status


def _normalize_date(value: Any) -> str | None:
    raw = str(value or "").strip()
    if not raw:
        return None
    parsed = pd.to_datetime(raw, errors="coerce")
    if pd.isna(parsed):
        return None
    return parsed.strftime("%Y-%m-%d")


def _parse_datetime(value: Any) -> datetime | None:
    parsed = pd.to_datetime(value, errors="coerce")
    if pd.isna(parsed):
        return None
    return parsed.to_pydatetime()


def _hour_to_slot(hour: int) -> str:
    if hour < 11:
        return "09:00-11:00"
    if hour < 13:
        return "11:00-13:00"
    if hour < 15:
        return "13:00-15:00"
    return "15:00+"


def _normalize_food_name(value: Any) -> str:
    return str(value or "").strip().lower()


def _infer_category(name: str) -> str:
    normalized = name.strip().lower()
    if any(token in normalized for token in ["dosa", "idli", "poha", "upma"]):
        return "breakfast"
    if any(token in normalized for token in ["tea", "coffee", "cola", "coke", "juice", "drink"]):
        return "beverage"
    if any(token in normalized for token in ["pizza", "biryani", "rice", "meal", "thali", "pasta", "noodles"]):
        return "meal"
    if any(token in normalized for token in ["sandwich", "wrap", "burger", "roll", "fries"]):
        return "snack"
    if any(token in normalized for token in ["cake", "ice cream", "sweet", "dessert"]):
        return "dessert"
    return "general"


def _infer_is_veg(name: str) -> int:
    normalized = name.strip().lower()
    non_veg_tokens = ["chicken", "egg", "mutton", "fish", "meat"]
    return 0 if any(token in normalized for token in non_veg_tokens) else 1


def _safe_read_dataset() -> pd.DataFrame:
    if not DATASET_PATH.exists():
        return pd.DataFrame()
    try:
        df = pd.read_csv(DATASET_PATH)
    except Exception:
        return pd.DataFrame()

    for column, default in DEFAULT_ROW.items():
        if column not in df.columns:
            df[column] = default
    if TARGET_COLUMN not in df.columns:
        df[TARGET_COLUMN] = 0
    if "date" not in df.columns:
        df["date"] = datetime.now().strftime("%Y-%m-%d")

    for column in NUMERIC_FEATURES + [TARGET_COLUMN]:
        df[column] = pd.to_numeric(df[column], errors="coerce")
    df[NUMERIC_FEATURES + [TARGET_COLUMN]] = df[NUMERIC_FEATURES + [TARGET_COLUMN]].fillna(0)

    for column in CATEGORICAL_FEATURES:
        df[column] = df[column].fillna(DEFAULT_ROW[column]).astype(str)

    df["date"] = pd.to_datetime(df["date"], errors="coerce").dt.strftime("%Y-%m-%d")
    return df


def _safe_read_orders() -> pd.DataFrame:
    rows = _safe_read_json(ORDERS_PATH, [])
    if not rows:
        return pd.DataFrame()

    df = pd.DataFrame(rows)
    if "food_item" not in df.columns:
        df["food_item"] = df.get("item", "")
    if "food_category" not in df.columns:
        df["food_category"] = df.get("category", "")
    if "quantity" not in df.columns:
        df["quantity"] = 1
    if "price" not in df.columns:
        df["price"] = 0

    parsed_time = pd.to_datetime(df.get("time"), errors="coerce")
    if "date" not in df.columns:
        df["date"] = parsed_time.dt.strftime("%Y-%m-%d")
    else:
        df["date"] = df["date"].apply(_normalize_date)
    if "time_slot" not in df.columns:
        df["time_slot"] = parsed_time.dt.hour.apply(
            lambda hour: _hour_to_slot(int(hour)) if pd.notna(hour) else DEFAULT_ROW["time_slot"]
        )

    df["food_item"] = df["food_item"].fillna("").astype(str).str.strip()
    df["food_category"] = df["food_category"].fillna("").astype(str).str.strip()
    df.loc[df["food_category"] == "", "food_category"] = df["food_item"].apply(_infer_category)
    df["quantity"] = pd.to_numeric(df["quantity"], errors="coerce").fillna(1).astype(int).clip(lower=1)
    df["price"] = pd.to_numeric(df["price"], errors="coerce").fillna(0).astype(int)
    df = df.dropna(subset=["date"])
    return df


def _safe_read_menu() -> list[dict[str, Any]]:
    rows = _safe_read_json(MENU_PATH, [])
    if not rows:
        return DEFAULT_MENU_ITEMS

    cleaned = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name", "")).strip()
        if not name:
            continue
        item_id = str(row.get("id") or row.get("item_id") or _normalize_food_name(name)).strip()
        cleaned.append(
            {
                "id": item_id,
                "name": name,
                "price": int(row.get("price", DEFAULT_ROW["price"]) or DEFAULT_ROW["price"]),
                "category": str(row.get("category", "")).strip().lower() or _infer_category(name),
            }
        )
    return cleaned or DEFAULT_MENU_ITEMS


def _safe_read_operations() -> pd.DataFrame:
    rows = _safe_read_json(OPERATIONS_PATH, [])
    if not rows:
        return pd.DataFrame()

    df = pd.DataFrame(rows)
    if "food_item" not in df.columns:
        return pd.DataFrame()

    if "food_category" not in df.columns:
        df["food_category"] = df.get("category", "")
    if "date" not in df.columns:
        df["date"] = datetime.now().strftime("%Y-%m-%d")
    if "time_slot" not in df.columns:
        df["time_slot"] = DEFAULT_ROW["time_slot"]
    if "price" not in df.columns:
        df["price"] = DEFAULT_ROW["price"]
    if "quantity_prepared" not in df.columns:
        df["quantity_prepared"] = 0
    if "quantity_sold" not in df.columns:
        df["quantity_sold"] = df.get("actual_sold", 0)
    if "quantity_wasted" not in df.columns:
        df["quantity_wasted"] = df.get("actual_wasted", 0)
    if "weather_type" not in df.columns:
        df["weather_type"] = DEFAULT_ROW["weather_type"]
    if "temperature" not in df.columns:
        df["temperature"] = DEFAULT_ROW["temperature"]
    if "is_holiday" not in df.columns:
        df["is_holiday"] = 0
    if "is_exam_day" not in df.columns:
        df["is_exam_day"] = 0
    if "is_veg" not in df.columns:
        df["is_veg"] = df["food_item"].apply(_infer_is_veg)
    if "portion_size" not in df.columns:
        df["portion_size"] = DEFAULT_ROW["portion_size"]
    if "is_special_item" not in df.columns:
        df["is_special_item"] = 0
    if "max_capacity" not in df.columns:
        df["max_capacity"] = DEFAULT_ROW["max_capacity"]
    if "staff_count" not in df.columns:
        df["staff_count"] = DEFAULT_ROW["staff_count"]

    df["food_item"] = df["food_item"].fillna("").astype(str).str.strip()
    df["food_category"] = df["food_category"].fillna("").astype(str).str.strip()
    df.loc[df["food_category"] == "", "food_category"] = df["food_item"].apply(_infer_category)
    df["date"] = df["date"].apply(_normalize_date)
    df["time_slot"] = df["time_slot"].fillna(DEFAULT_ROW["time_slot"]).astype(str)
    df["weather_type"] = df["weather_type"].fillna(DEFAULT_ROW["weather_type"]).astype(str)

    numeric_columns = [
        "price",
        "quantity_prepared",
        "quantity_sold",
        "quantity_wasted",
        "temperature",
        "is_holiday",
        "is_exam_day",
        "is_veg",
        "portion_size",
        "is_special_item",
        "max_capacity",
        "staff_count",
    ]
    for column in numeric_columns:
        df[column] = pd.to_numeric(df[column], errors="coerce").fillna(0)

    df = df.dropna(subset=["date"])
    return df


def _safe_read_prediction_logs() -> list[dict[str, Any]]:
    rows = _safe_read_json(PREDICTION_LOGS_PATH, [])
    return rows if isinstance(rows, list) else []


def _dedupe_live_rows(df: pd.DataFrame) -> pd.DataFrame:
    if df.empty:
        return df
    keys = [column for column in ["date", "food_item", "time_slot"] if column in df.columns]
    if not keys:
        return df
    return df.drop_duplicates(subset=keys, keep="last")


def _item_profile(
    food_item: str,
    dataset_df: pd.DataFrame,
    orders_df: pd.DataFrame,
    operations_df: pd.DataFrame,
) -> dict[str, Any]:
    normalized_food = _normalize_food_name(food_item)
    dataset_slice = pd.DataFrame()
    if not dataset_df.empty and "food_item" in dataset_df.columns:
        dataset_slice = dataset_df[
            dataset_df["food_item"].astype(str).str.lower() == normalized_food
        ]

    orders_slice = pd.DataFrame()
    if not orders_df.empty and "food_item" in orders_df.columns:
        orders_slice = orders_df[
            orders_df["food_item"].astype(str).str.lower() == normalized_food
        ]

    operations_slice = pd.DataFrame()
    if not operations_df.empty and "food_item" in operations_df.columns:
        operations_slice = operations_df[
            operations_df["food_item"].astype(str).str.lower() == normalized_food
        ]

    def _safe_profile_number(value: Any, fallback: float) -> float:
        try:
            parsed = float(value)
        except Exception:
            return fallback
        if np.isnan(parsed):
            return fallback
        return parsed

    category = (
        dataset_slice["food_category"].mode().iloc[0]
        if not dataset_slice.empty and "food_category" in dataset_slice.columns
        else (
            operations_slice["food_category"].mode().iloc[0]
            if not operations_slice.empty and "food_category" in operations_slice.columns
            else (
                orders_slice["food_category"].mode().iloc[0]
                if not orders_slice.empty and "food_category" in orders_slice.columns
                else _infer_category(food_item)
            )
        )
    )

    price = (
        float(dataset_slice["price"].mean())
        if not dataset_slice.empty and "price" in dataset_slice.columns
        else (
            float(operations_slice["price"].mean())
            if not operations_slice.empty and "price" in operations_slice.columns
            else (
                float(orders_slice["price"].mean())
                if not orders_slice.empty and "price" in orders_slice.columns
                else float(DEFAULT_ROW["price"])
            )
        )
    )

    return {
        "food_category": category,
        "is_veg": int(
            round(
                _safe_profile_number(
                    dataset_slice["is_veg"].mean()
                    if not dataset_slice.empty and "is_veg" in dataset_slice.columns
                    else _infer_is_veg(food_item),
                    float(_infer_is_veg(food_item)),
                )
            )
        ),
        "price": int(round(_safe_profile_number(price, float(DEFAULT_ROW["price"])))),
        "portion_size": _safe_profile_number(
            dataset_slice["portion_size"].mean()
            if not dataset_slice.empty and "portion_size" in dataset_slice.columns
            else DEFAULT_ROW["portion_size"],
            float(DEFAULT_ROW["portion_size"]),
        ),
        "is_special_item": int(
            round(
                _safe_profile_number(
                    dataset_slice["is_special_item"].mean()
                    if not dataset_slice.empty and "is_special_item" in dataset_slice.columns
                    else DEFAULT_ROW["is_special_item"],
                    float(DEFAULT_ROW["is_special_item"]),
                )
            )
        ),
        "quantity_prepared": _safe_profile_number(
            dataset_slice["quantity_prepared"].mean()
            if not dataset_slice.empty and "quantity_prepared" in dataset_slice.columns
            else (
                operations_slice["quantity_prepared"].mean()
                if not operations_slice.empty and "quantity_prepared" in operations_slice.columns
                else DEFAULT_ROW["quantity_prepared"]
            ),
            float(DEFAULT_ROW["quantity_prepared"]),
        ),
        "quantity_wasted": _safe_profile_number(
            dataset_slice["quantity_wasted"].mean()
            if not dataset_slice.empty and "quantity_wasted" in dataset_slice.columns
            else (
                operations_slice["quantity_wasted"].mean()
                if not operations_slice.empty and "quantity_wasted" in operations_slice.columns
                else DEFAULT_ROW["quantity_wasted"]
            ),
            float(DEFAULT_ROW["quantity_wasted"]),
        ),
        "leftover_percentage": _safe_profile_number(
            dataset_slice["leftover_percentage"].mean()
            if not dataset_slice.empty and "leftover_percentage" in dataset_slice.columns
            else DEFAULT_ROW["leftover_percentage"],
            float(DEFAULT_ROW["leftover_percentage"]),
        ),
        "max_capacity": _safe_profile_number(
            dataset_slice["max_capacity"].mean()
            if not dataset_slice.empty and "max_capacity" in dataset_slice.columns
            else DEFAULT_ROW["max_capacity"],
            float(DEFAULT_ROW["max_capacity"]),
        ),
        "staff_count": _safe_profile_number(
            dataset_slice["staff_count"].mean()
            if not dataset_slice.empty and "staff_count" in dataset_slice.columns
            else DEFAULT_ROW["staff_count"],
            float(DEFAULT_ROW["staff_count"]),
        ),
        "weather_type": (
            dataset_slice["weather_type"].mode().iloc[0]
            if not dataset_slice.empty and "weather_type" in dataset_slice.columns
            else (
                operations_slice["weather_type"].mode().iloc[0]
                if not operations_slice.empty and "weather_type" in operations_slice.columns
                else DEFAULT_ROW["weather_type"]
            )
        ),
        "historical_average_sales": _safe_profile_number(
            dataset_slice[TARGET_COLUMN].mean()
            if not dataset_slice.empty and TARGET_COLUMN in dataset_slice.columns
            else (
                operations_slice["quantity_sold"].mean()
                if not operations_slice.empty and "quantity_sold" in operations_slice.columns
                else (
                    orders_slice["quantity"].mean()
                    if not orders_slice.empty
                    else DEFAULT_ROW["avg_last_7_days_sales"]
                )
            ),
            float(DEFAULT_ROW["avg_last_7_days_sales"]),
        ),
    }


def _build_live_training_rows(
    dataset_df: pd.DataFrame,
    orders_df: pd.DataFrame,
    operations_df: pd.DataFrame,
) -> pd.DataFrame:
    if orders_df.empty and operations_df.empty:
        return pd.DataFrame(columns=["date", *FEATURE_COLUMNS, TARGET_COLUMN])

    rows = []
    if not orders_df.empty:
        grouped = (
            orders_df.groupby(["date", "food_item", "time_slot"], dropna=False)
            .agg(
                quantity_sold=("quantity", "sum"),
                price=("price", "mean"),
                food_category=("food_category", lambda series: series.mode().iloc[0] if not series.mode().empty else ""),
            )
            .reset_index()
        )
        grouped["date_parsed"] = pd.to_datetime(grouped["date"], errors="coerce")
        grouped = grouped.dropna(subset=["date_parsed"]).sort_values(by="date_parsed")

        for _, row in grouped.iterrows():
            target_date = row["date_parsed"].to_pydatetime()
            features = build_live_feature_payload(
                {
                    "food_item": row["food_item"],
                    "time_slot": row["time_slot"],
                    "price": row["price"],
                    "food_category": row["food_category"],
                    "date": target_date.strftime("%Y-%m-%d"),
                    "skip_live_orders_on_target": True,
                },
                dataset_df=dataset_df,
                orders_df=orders_df,
                operations_df=operations_df,
            )
            feature_row = dict(features["features"])
            feature_row["date"] = target_date.strftime("%Y-%m-%d")
            feature_row[TARGET_COLUMN] = int(row["quantity_sold"])
            rows.append(feature_row)

    if not operations_df.empty:
        grouped_operations = (
            operations_df.groupby(["date", "food_item", "time_slot"], dropna=False)
            .agg(
                quantity_prepared=("quantity_prepared", "sum"),
                quantity_sold=("quantity_sold", "sum"),
                quantity_wasted=("quantity_wasted", "sum"),
                price=("price", "mean"),
                food_category=("food_category", lambda series: series.mode().iloc[0] if not series.mode().empty else ""),
                weather_type=("weather_type", lambda series: series.mode().iloc[0] if not series.mode().empty else DEFAULT_ROW["weather_type"]),
                temperature=("temperature", "mean"),
                is_holiday=("is_holiday", "max"),
                is_exam_day=("is_exam_day", "max"),
                is_veg=("is_veg", "max"),
                portion_size=("portion_size", "mean"),
                is_special_item=("is_special_item", "max"),
                max_capacity=("max_capacity", "mean"),
                staff_count=("staff_count", "mean"),
            )
            .reset_index()
        )
        grouped_operations["date_parsed"] = pd.to_datetime(grouped_operations["date"], errors="coerce")
        grouped_operations = grouped_operations.dropna(subset=["date_parsed"]).sort_values(by="date_parsed")

        for _, row in grouped_operations.iterrows():
            target_date = row["date_parsed"].to_pydatetime()
            features = build_live_feature_payload(
                {
                    "food_item": row["food_item"],
                    "time_slot": row["time_slot"],
                    "price": row["price"],
                    "food_category": row["food_category"],
                    "weather_type": row["weather_type"],
                    "temperature": row["temperature"],
                    "is_holiday": row["is_holiday"],
                    "is_exam_day": row["is_exam_day"],
                    "is_veg": row["is_veg"],
                    "portion_size": row["portion_size"],
                    "is_special_item": row["is_special_item"],
                    "max_capacity": row["max_capacity"],
                    "staff_count": row["staff_count"],
                    "date": target_date.strftime("%Y-%m-%d"),
                    "skip_live_orders_on_target": True,
                },
                dataset_df=dataset_df,
                orders_df=orders_df,
                operations_df=operations_df,
            )
            feature_row = dict(features["features"])
            feature_row["date"] = target_date.strftime("%Y-%m-%d")
            feature_row["quantity_prepared"] = float(row["quantity_prepared"])
            feature_row["quantity_wasted"] = float(row["quantity_wasted"])
            feature_row[TARGET_COLUMN] = int(row["quantity_sold"])
            rows.append(feature_row)

    return pd.DataFrame(rows)


def _build_preprocessor() -> ColumnTransformer:
    numeric_pipeline = Pipeline(
        steps=[
            ("imputer", SimpleImputer(strategy="median")),
            ("scaler", StandardScaler()),
        ]
    )
    categorical_pipeline = Pipeline(
        steps=[
            ("imputer", SimpleImputer(strategy="most_frequent")),
            ("encoder", OneHotEncoder(handle_unknown="ignore")),
        ]
    )
    return ColumnTransformer(
        transformers=[
            ("numeric", numeric_pipeline, NUMERIC_FEATURES),
            ("categorical", categorical_pipeline, CATEGORICAL_FEATURES),
        ]
    )


def _extract_top_features(fitted_pipeline: Pipeline, limit: int = 10) -> list[dict[str, Any]]:
    try:
        preprocess = fitted_pipeline.named_steps["preprocess"]
        model = fitted_pipeline.named_steps["model"]
        feature_names = preprocess.get_feature_names_out()
    except Exception:
        return []

    if hasattr(model, "feature_importances_"):
        weights = np.asarray(model.feature_importances_)
    elif hasattr(model, "coef_"):
        weights = np.abs(np.asarray(model.coef_).ravel())
    else:
        return []

    if weights.size != len(feature_names):
        return []

    order = np.argsort(weights)[::-1][:limit]
    return [
        {
            "feature": str(feature_names[index]),
            "importance": round(float(weights[index]), 6),
        }
        for index in order
    ]


def train_models() -> dict[str, Any]:
    dataset_df = _safe_read_dataset()
    orders_df = _safe_read_orders()
    operations_df = _safe_read_operations()
    live_rows_df = _build_live_training_rows(dataset_df, orders_df, operations_df)

    training_df = dataset_df.copy()
    if not live_rows_df.empty:
        training_df = pd.concat([training_df, live_rows_df], ignore_index=True)
    if training_df.empty:
        raise ValueError("No dataset rows available for training.")

    for column, default in DEFAULT_ROW.items():
        if column not in training_df.columns:
            training_df[column] = default
    if TARGET_COLUMN not in training_df.columns:
        raise ValueError("Training dataset is missing quantity_sold.")
    if "date" not in training_df.columns:
        training_df["date"] = datetime.now().strftime("%Y-%m-%d")

    training_df = _dedupe_live_rows(training_df)
    training_df[FEATURE_COLUMNS] = training_df[FEATURE_COLUMNS].copy()

    for column in NUMERIC_FEATURES + [TARGET_COLUMN]:
        training_df[column] = pd.to_numeric(training_df[column], errors="coerce")
    training_df[NUMERIC_FEATURES + [TARGET_COLUMN]] = training_df[NUMERIC_FEATURES + [TARGET_COLUMN]].fillna(0)
    for column in CATEGORICAL_FEATURES:
        training_df[column] = training_df[column].fillna(DEFAULT_ROW[column]).astype(str)

    training_df["date"] = pd.to_datetime(training_df["date"], errors="coerce").dt.strftime("%Y-%m-%d")
    training_df = training_df.dropna(subset=[TARGET_COLUMN])

    training_df.to_csv(DATASET_PATH, index=False)

    X = training_df[FEATURE_COLUMNS].copy()
    y = training_df[TARGET_COLUMN].astype(float)

    X_train, X_test, y_train, y_test = train_test_split(
        X,
        y,
        test_size=0.2,
        random_state=42,
    )

    preprocessor = _build_preprocessor()
    candidate_models = {
        "Linear Regression": LinearRegression(),
        "Random Forest": RandomForestRegressor(
            n_estimators=160,
            max_depth=14,
            min_samples_leaf=2,
            random_state=42,
        ),
        "Gradient Boosting": GradientBoostingRegressor(random_state=42),
    }

    best_name = ""
    best_pipeline = None
    best_score = float("-inf")
    metrics = {}

    for name, model in candidate_models.items():
        pipeline = Pipeline(
            steps=[
                ("preprocess", preprocessor),
                ("model", model),
            ]
        )
        pipeline.fit(X_train, y_train)
        predictions = pipeline.predict(X_test)

        mae = mean_absolute_error(y_test, predictions)
        mse = mean_squared_error(y_test, predictions)
        r2 = r2_score(y_test, predictions)
        metrics[name] = {
            "mae": round(float(mae), 4),
            "mse": round(float(mse), 4),
            "r2": round(float(r2), 4),
        }

        model_filename = MODELS_DIR / f"{name.lower().replace(' ', '_')}.pkl"
        joblib.dump(pipeline, model_filename)

        if r2 > best_score:
            best_score = r2
            best_name = name
            best_pipeline = pipeline

    if best_pipeline is None:
        raise RuntimeError("Training did not produce a model.")

    top_features = _extract_top_features(best_pipeline)
    metrics_payload = {
        "trained_at": datetime.now().isoformat(),
        "dataset_rows": int(len(training_df)),
        "live_rows_added": int(len(live_rows_df)),
        "train_rows": int(len(X_train)),
        "test_rows": int(len(X_test)),
        "best_model_name": best_name,
        "best_r2": round(float(best_score), 4),
        "feature_columns": FEATURE_COLUMNS,
        "models": metrics,
        "top_features": top_features,
    }

    bundle = {
        "pipeline": best_pipeline,
        "best_model_name": best_name,
        "metrics": metrics_payload,
        "feature_columns": FEATURE_COLUMNS,
        "trained_at": metrics_payload["trained_at"],
        "top_features": top_features,
    }

    joblib.dump(bundle, MODEL_BUNDLE_PATH)
    joblib.dump(best_pipeline, BEST_MODEL_PATH)
    _safe_write_json(TRAINING_METRICS_PATH, metrics_payload)
    return metrics_payload


def run_training_cycle(trigger: str = "manual") -> dict[str, Any]:
    started_at = datetime.now()
    current_status = get_training_status()
    running_status = {
        **current_status,
        "status": "running",
        "status_label": "Training in progress",
        "last_started_at": started_at.isoformat(),
        "last_trigger": trigger,
        "last_error": None,
    }
    _safe_write_json(TRAINING_STATUS_PATH, running_status)

    try:
        metrics = train_models()
        completed_at = datetime.now()
        duration_seconds = round((completed_at - started_at).total_seconds(), 2)
        snapshot = _snapshot_training_metrics(metrics)
        success_status = {
            **running_status,
            **snapshot,
            "status": "success",
            "status_label": "Healthy",
            "last_completed_at": metrics.get("trained_at") or completed_at.isoformat(),
            "last_duration_seconds": duration_seconds,
        }
        _safe_write_json(TRAINING_STATUS_PATH, success_status)
        _append_training_history(
            {
                "status": "success",
                "trigger": trigger,
                "started_at": running_status["last_started_at"],
                "completed_at": success_status["last_completed_at"],
                "duration_seconds": duration_seconds,
                **snapshot,
            }
        )
        return metrics
    except Exception as exc:
        completed_at = datetime.now()
        duration_seconds = round((completed_at - started_at).total_seconds(), 2)
        failure_status = {
            **current_status,
            "status": "failed",
            "status_label": "Needs attention",
            "last_started_at": running_status["last_started_at"],
            "last_completed_at": completed_at.isoformat(),
            "last_trigger": trigger,
            "last_error": str(exc),
            "last_duration_seconds": duration_seconds,
        }
        _safe_write_json(TRAINING_STATUS_PATH, failure_status)
        _append_training_history(
            {
                "status": "failed",
                "trigger": trigger,
                "started_at": running_status["last_started_at"],
                "completed_at": completed_at.isoformat(),
                "duration_seconds": duration_seconds,
                "error": str(exc),
                **_snapshot_training_metrics(),
            }
        )
        raise


def load_model_bundle() -> dict[str, Any]:
    if MODEL_BUNDLE_PATH.exists():
        try:
            bundle = joblib.load(MODEL_BUNDLE_PATH)
            if isinstance(bundle, dict) and "pipeline" in bundle:
                return bundle
        except Exception:
            pass

    if BEST_MODEL_PATH.exists():
        try:
            pipeline = joblib.load(BEST_MODEL_PATH)
            return {
                "pipeline": pipeline,
                "best_model_name": "Saved Model",
                "metrics": _safe_read_json(TRAINING_METRICS_PATH, {}),
                "top_features": _safe_read_json(TRAINING_METRICS_PATH, {}).get("top_features", []),
            }
        except Exception:
            pass
    return {}


def _series_average(series: pd.Series) -> float:
    if series.empty:
        return 0.0
    return float(series.mean())


def _clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(upper, value))


def build_live_feature_payload(
    input_data: dict[str, Any],
    *,
    dataset_df: pd.DataFrame | None = None,
    orders_df: pd.DataFrame | None = None,
    operations_df: pd.DataFrame | None = None,
) -> dict[str, Any]:
    dataset_df = _safe_read_dataset() if dataset_df is None else dataset_df
    orders_df = _safe_read_orders() if orders_df is None else orders_df
    operations_df = _safe_read_operations() if operations_df is None else operations_df

    food_item = str(input_data.get("food_item", DEFAULT_ROW["food_item"])).strip() or DEFAULT_ROW["food_item"]
    target_dt = (
        _parse_datetime(input_data.get("target_datetime"))
        or _parse_datetime(input_data.get("date"))
        or datetime.now()
    )
    target_date = target_dt.strftime("%Y-%m-%d")
    time_slot = str(input_data.get("time_slot", "")).strip() or _hour_to_slot(target_dt.hour)

    profile = _item_profile(food_item, dataset_df, orders_df, operations_df)
    training_metrics = get_training_metrics()

    normalized_food = _normalize_food_name(food_item)
    dataset_item_rows = pd.DataFrame()
    if not dataset_df.empty:
        dataset_item_rows = dataset_df[
            dataset_df["food_item"].astype(str).str.lower() == normalized_food
        ].copy()

    item_orders = pd.DataFrame()
    if not orders_df.empty:
        item_orders = orders_df[
            orders_df["food_item"].astype(str).str.lower() == normalized_food
        ].copy()

    item_operations = pd.DataFrame()
    if not operations_df.empty:
        item_operations = operations_df[
            operations_df["food_item"].astype(str).str.lower() == normalized_food
        ].copy()

    if not item_orders.empty:
        item_orders["date_parsed"] = pd.to_datetime(item_orders["date"], errors="coerce")
        if input_data.get("skip_live_orders_on_target"):
            item_orders = item_orders[item_orders["date"] < target_date]

    if not item_operations.empty:
        item_operations["date_parsed"] = pd.to_datetime(item_operations["date"], errors="coerce")
        if input_data.get("skip_live_orders_on_target"):
            item_operations = item_operations[item_operations["date"] < target_date]

    prev_day_key = (target_dt - timedelta(days=1)).strftime("%Y-%m-%d")
    prev_week_key = (target_dt - timedelta(days=7)).strftime("%Y-%m-%d")

    sales_source = item_operations if not item_operations.empty else item_orders
    sales_quantity_column = "quantity_sold" if not item_operations.empty else "quantity"

    same_slot_orders = (
        sales_source[sales_source["time_slot"] == time_slot] if not sales_source.empty else pd.DataFrame()
    )
    dataset_same_slot_rows = (
        dataset_item_rows[dataset_item_rows["time_slot"] == time_slot]
        if not dataset_item_rows.empty
        else pd.DataFrame()
    )
    prev_day_sales = int(
        sales_source.loc[sales_source["date"] == prev_day_key, sales_quantity_column].sum()
    ) if not sales_source.empty else 0
    prev_same_slot_sales = (
        _series_average(same_slot_orders[sales_quantity_column]) if not same_slot_orders.empty else 0.0
    )
    prev_week_same_day_slot_sales = float(
        same_slot_orders.loc[same_slot_orders["date"] == prev_week_key, sales_quantity_column].sum()
    ) if not same_slot_orders.empty else 0.0

    daily_item_sales = pd.DataFrame()
    if not sales_source.empty:
        daily_item_sales = (
            sales_source.groupby("date", dropna=False)[sales_quantity_column].sum().reset_index()
        )
        daily_item_sales["date_parsed"] = pd.to_datetime(daily_item_sales["date"], errors="coerce")
        daily_item_sales = daily_item_sales.dropna(subset=["date_parsed"]).sort_values(by="date_parsed")
        daily_item_sales = daily_item_sales.rename(columns={sales_quantity_column: "quantity"})

    recent_daily_sales = daily_item_sales["quantity"].tail(7) if not daily_item_sales.empty else pd.Series(dtype=float)
    recent_three_sales = daily_item_sales["quantity"].tail(3) if not daily_item_sales.empty else pd.Series(dtype=float)
    earlier_three_sales = (
        daily_item_sales["quantity"].iloc[max(len(daily_item_sales) - 6, 0):max(len(daily_item_sales) - 3, 0)]
        if not daily_item_sales.empty
        else pd.Series(dtype=float)
    )

    avg_last_3_days_sales = _series_average(recent_three_sales) or profile["historical_average_sales"]
    avg_last_7_days_sales = _series_average(recent_daily_sales) or profile["historical_average_sales"]
    previous_window_average = _series_average(earlier_three_sales)
    sales_trend_3_days = avg_last_3_days_sales - previous_window_average
    sales_trend_weekly = avg_last_7_days_sales - float(profile["historical_average_sales"])
    demand_variance = float(recent_daily_sales.std(ddof=0)) if len(recent_daily_sales) > 1 else 0.0

    quantity_prepared = max(
        float(profile["quantity_prepared"]),
        float(avg_last_7_days_sales * 1.12),
        float(prev_day_sales * 1.05),
        float(DEFAULT_ROW["quantity_prepared"] if avg_last_7_days_sales == 0 else 0),
    )
    quantity_wasted = max(float(profile["quantity_wasted"]), quantity_prepared - avg_last_7_days_sales, 0.0)
    leftover_percentage = (
        (quantity_wasted / quantity_prepared) * 100 if quantity_prepared > 0 else profile["leftover_percentage"]
    )

    missing_components = 0
    for value in [prev_day_sales, prev_same_slot_sales, prev_week_same_day_slot_sales]:
        if float(value) == 0:
            missing_components += 1

    live_history_points = int(sales_source[sales_quantity_column].count()) if not sales_source.empty else 0
    live_same_slot_points = int(same_slot_orders[sales_quantity_column].count()) if not same_slot_orders.empty else 0
    dataset_history_points = int(len(dataset_item_rows)) if not dataset_item_rows.empty else 0
    dataset_same_slot_points = int(len(dataset_same_slot_rows)) if not dataset_same_slot_rows.empty else 0

    history_points = dataset_history_points + live_history_points
    same_slot_points = dataset_same_slot_points + live_same_slot_points
    observed_recent_days = int(len(recent_daily_sales))

    history_coverage = _clamp(
        (dataset_history_points * 0.4 + live_history_points * 1.4) / 24.0,
        0.0,
        1.0,
    )
    slot_coverage = _clamp(
        (dataset_same_slot_points * 0.35 + live_same_slot_points * 1.6) / 10.0,
        0.0,
        1.0,
    )
    recency_coverage = _clamp(observed_recent_days / 7.0, 0.0, 1.0)
    if observed_recent_days == 0 and dataset_history_points > 0:
        recency_coverage = _clamp(dataset_history_points / 60.0, 0.0, 1.0) * 0.45

    demand_anchor_for_variation = max(avg_last_7_days_sales, float(profile["historical_average_sales"]), 1.0)
    coefficient_of_variation = demand_variance / demand_anchor_for_variation
    stability_score = _clamp(1.0 - min(coefficient_of_variation, 1.5) / 1.5, 0.0, 1.0)
    completeness_score = _clamp(1.0 - (missing_components / 4.0), 0.0, 1.0)
    model_quality_score = _clamp(float(training_metrics.get("best_r2", 0.0) or 0.0), 0.0, 1.0)

    confidence_score = _clamp(
        (
            history_coverage * 22.0
            + slot_coverage * 18.0
            + recency_coverage * 16.0
            + stability_score * 14.0
            + completeness_score * 9.0
            + model_quality_score * 10.0
        ),
        18.0,
        96.0,
    )
    confidence_label = (
        "High" if confidence_score >= 76 else "Medium" if confidence_score >= 50 else "Low"
    )

    confidence_reason = "Live data is still limited, so this forecast leans heavily on historical patterns."
    if history_points <= 2:
        confidence_reason = "Very little item history is available yet, so this forecast is mostly exploratory."
    elif live_history_points == 0 and dataset_history_points > 0:
        confidence_reason = "Historical dataset coverage is strong, but recent live canteen logs for this item are limited."
    elif same_slot_points <= 2:
        confidence_reason = "This item has history, but not much for this exact time slot yet."
    elif coefficient_of_variation >= 0.45:
        confidence_reason = "Recent demand is volatile, so the forecast includes more uncertainty than usual."
    elif confidence_label == "High":
        confidence_reason = "Strong historical coverage, slot-level support, and stable demand patterns back this forecast."

    trend_direction = "stable"
    trend_reason = "Demand is close to the recent average."
    if sales_trend_weekly > 3:
        trend_direction = "up"
        trend_reason = "Recent weekly sales are running above the historical average."
    elif sales_trend_weekly < -3:
        trend_direction = "down"
        trend_reason = "Recent weekly sales are running below the historical average."

    action = "Keep preparation close to the recent average."
    if prev_day_sales > avg_last_7_days_sales * 1.1:
        action = "Increase preparation slightly to cover rising demand."
    elif demand_variance > 12:
        action = "Prepare carefully and monitor live demand; recent sales are volatile."
    elif avg_last_7_days_sales < profile["historical_average_sales"] * 0.9:
        action = "Reduce preparation slightly to avoid over-preparation."

    features = {
        "day_of_week": target_dt.weekday(),
        "week_of_year": int(target_dt.isocalendar()[1]),
        "month": target_dt.month,
        "time_slot": time_slot,
        "is_weekend": 1 if target_dt.weekday() >= 5 else 0,
        "is_holiday": int(input_data.get("is_holiday") or 0),
        "is_exam_day": int(input_data.get("is_exam_day") or 0),
        "food_item": food_item,
        "food_category": str(input_data.get("food_category") or profile["food_category"]),
        "is_veg": int(input_data.get("is_veg") if input_data.get("is_veg") is not None else profile["is_veg"]),
        "price": float(input_data.get("price") if input_data.get("price") is not None else profile["price"]),
        "portion_size": float(
            input_data.get("portion_size")
            if input_data.get("portion_size") is not None
            else profile["portion_size"]
        ),
        "is_special_item": int(
            input_data.get("is_special_item")
            if input_data.get("is_special_item") is not None
            else profile["is_special_item"]
        ),
        "prev_day_sales": float(prev_day_sales),
        "prev_same_slot_sales": float(prev_same_slot_sales),
        "prev_week_same_day_slot_sales": float(prev_week_same_day_slot_sales),
        "avg_last_3_days_sales": float(avg_last_3_days_sales),
        "avg_last_7_days_sales": float(avg_last_7_days_sales),
        "sales_trend_3_days": float(sales_trend_3_days),
        "sales_trend_weekly": float(sales_trend_weekly),
        "demand_variance": float(demand_variance),
        "quantity_prepared": float(quantity_prepared),
        "quantity_wasted": float(quantity_wasted),
        "leftover_percentage": float(leftover_percentage),
        "max_capacity": float(
            input_data.get("max_capacity")
            if input_data.get("max_capacity") is not None
            else profile["max_capacity"]
        ),
        "staff_count": float(
            input_data.get("staff_count")
            if input_data.get("staff_count") is not None
            else profile["staff_count"]
        ),
        "weather_type": str(input_data.get("weather_type") or profile["weather_type"]),
        "temperature": float(
            input_data.get("temperature")
            if input_data.get("temperature") is not None
            else DEFAULT_ROW["temperature"]
        ),
    }

    meta = {
        "target_date": target_date,
        "time_slot": time_slot,
        "food_item": food_item,
        "historical_average_sales": round(float(profile["historical_average_sales"]), 2),
        "recent_average_sales": round(float(avg_last_7_days_sales), 2),
        "historical_preparation_average": int(round(float(profile["quantity_prepared"]))),
        "historical_waste_average": round(float(profile["quantity_wasted"]), 2),
        "confidence_score": round(float(confidence_score), 2),
        "confidence_label": confidence_label,
        "confidence_reason": confidence_reason,
        "trend_direction": trend_direction,
        "trend_reason": trend_reason,
        "recommended_action": action,
        "history_points": history_points,
        "same_slot_points": same_slot_points,
        "feature_snapshot": {
            "prev_day_sales": int(prev_day_sales),
            "prev_same_slot_sales": round(float(prev_same_slot_sales), 2),
            "prev_week_same_day_slot_sales": round(float(prev_week_same_day_slot_sales), 2),
            "avg_last_3_days_sales": round(float(avg_last_3_days_sales), 2),
            "avg_last_7_days_sales": round(float(avg_last_7_days_sales), 2),
            "sales_trend_3_days": round(float(sales_trend_3_days), 2),
            "sales_trend_weekly": round(float(sales_trend_weekly), 2),
            "demand_variance": round(float(demand_variance), 2),
            "history_points": history_points,
            "same_slot_points": same_slot_points,
            "dataset_history_points": dataset_history_points,
            "dataset_same_slot_points": dataset_same_slot_points,
            "live_history_points": live_history_points,
            "live_same_slot_points": live_same_slot_points,
            "coefficient_of_variation": round(float(coefficient_of_variation), 3),
            "completeness_score": round(float(completeness_score), 3),
        },
    }

    return {"features": features, "meta": meta}


def predict_live_demand(
    input_data: dict[str, Any],
    *,
    log_request: bool = True,
    source: str = "prediction_request",
) -> dict[str, Any]:
    from log_prediction import log_prediction

    dataset_df = _safe_read_dataset()
    orders_df = _safe_read_orders()
    operations_df = _safe_read_operations()
    payload = build_live_feature_payload(
        input_data,
        dataset_df=dataset_df,
        orders_df=orders_df,
        operations_df=operations_df,
    )
    features = payload["features"]
    meta = payload["meta"]

    bundle = load_model_bundle()
    pipeline = bundle.get("pipeline")
    model_name = bundle.get("best_model_name", "Heuristic fallback")

    frame = pd.DataFrame([features])[FEATURE_COLUMNS]
    if pipeline is None:
        model_predicted_demand = int(round(max(features["avg_last_7_days_sales"], DEFAULT_ROW["avg_last_7_days_sales"])))
        model_name = "Heuristic fallback"
    else:
        predicted_raw = pipeline.predict(frame)[0]
        model_predicted_demand = int(round(max(float(predicted_raw), 0)))

    confidence_weight = _clamp(float(meta["confidence_score"]) / 100.0, 0.25, 0.88)
    expected_demand_anchor = (
        model_predicted_demand * confidence_weight
        + float(meta["recent_average_sales"]) * (1.0 - confidence_weight)
    )
    if float(features["prev_day_sales"]) > 0:
        expected_demand_anchor = (
            expected_demand_anchor * 0.8
            + float(features["prev_day_sales"]) * 0.2
        )
    predicted_demand = int(round(max(float(expected_demand_anchor), 0)))

    coefficient_of_variation = float(
        meta["feature_snapshot"].get("coefficient_of_variation", 0.0) or 0.0
    )
    base_buffer = 0.06
    if meta["confidence_label"] == "Low":
        base_buffer = 0.18
    elif meta["confidence_label"] == "Medium":
        base_buffer = 0.11
    volatility_buffer = _clamp(coefficient_of_variation, 0.0, 0.35) * 0.25
    trend_adjustment = 0.04 if meta["trend_direction"] == "up" else -0.02 if meta["trend_direction"] == "down" else 0.0
    buffer_ratio = _clamp(base_buffer + volatility_buffer + trend_adjustment, 0.05, 0.28)

    suggested_preparation = int(round(predicted_demand * (1.0 + buffer_ratio)))
    expected_waste = max(suggested_preparation - predicted_demand, 0)
    expected_sell_through = round(
        (predicted_demand / suggested_preparation * 100.0) if suggested_preparation else 0.0,
        2,
    )

    result = {
        "food_item": meta["food_item"],
        "food_category": features["food_category"],
        "predicted_demand": predicted_demand,
        "model_predicted_demand": model_predicted_demand,
        "suggested_preparation": suggested_preparation,
        "expected_waste": expected_waste,
        "expected_demand_anchor": round(float(expected_demand_anchor), 2),
        "recommended_buffer_percentage": round(float(buffer_ratio * 100.0), 2),
        "expected_sell_through_percentage": expected_sell_through,
        "historical_average_sales": meta["historical_average_sales"],
        "recent_average_sales": meta["recent_average_sales"],
        "historical_preparation_average": meta["historical_preparation_average"],
        "historical_waste_average": meta["historical_waste_average"],
        "confidence_score": meta["confidence_score"],
        "confidence_label": meta["confidence_label"],
        "confidence_reason": meta["confidence_reason"],
        "trend_direction": meta["trend_direction"],
        "trend_reason": meta["trend_reason"],
        "recommended_action": meta["recommended_action"],
        "time_slot": meta["time_slot"],
        "target_date": meta["target_date"],
        "weather_type": features["weather_type"],
        "temperature": int(round(features["temperature"])),
        "model_name": model_name,
        "feature_snapshot": meta["feature_snapshot"],
    }

    if log_request:
        log_prediction(
            food_item=meta["food_item"],
            predicted_demand=predicted_demand,
            suggested_preparation=suggested_preparation,
            actual_sold=None,
            target_date=meta["target_date"],
            time_slot=meta["time_slot"],
            source=source,
            historical_baseline_actual=predicted_demand,
            historical_preparation_average=meta["historical_preparation_average"],
            confidence_score=meta["confidence_score"],
            confidence_label=meta["confidence_label"],
            model_name=model_name,
            feature_snapshot=meta["feature_snapshot"],
            expected_waste=expected_waste,
        )

    return result


def get_forecast_menu_items(limit: int | None = None) -> list[dict[str, Any]]:
    menu_rows = _safe_read_menu()
    if menu_rows:
        return menu_rows[:limit] if limit is not None else menu_rows

    dataset_df = _safe_read_dataset()
    operations_df = _safe_read_operations()
    if not dataset_df.empty:
        top_items = (
            dataset_df.groupby("food_item")[TARGET_COLUMN]
            .mean()
            .sort_values(ascending=False)
            .head(limit or len(dataset_df))
            .index.tolist()
        )
        return [
            {
                "name": item,
                "price": int(round(_item_profile(item, dataset_df, _safe_read_orders(), operations_df)["price"])),
                "category": _item_profile(item, dataset_df, _safe_read_orders(), operations_df)["food_category"],
            }
            for item in top_items
        ]
    return DEFAULT_MENU_ITEMS[:limit] if limit is not None else DEFAULT_MENU_ITEMS


def build_demand_dashboard(
    *,
    target_datetime: datetime | None = None,
    time_slot: str | None = None,
    weather_type: str | None = None,
    temperature: int | None = None,
    log_request: bool = True,
) -> dict[str, Any]:
    target_datetime = target_datetime or datetime.now()
    menu_rows = get_forecast_menu_items()
    rows = []

    for item in menu_rows:
        prediction = predict_live_demand(
            {
                "food_item": item["name"],
                "price": item.get("price", DEFAULT_ROW["price"]),
                "food_category": item.get("category", _infer_category(item["name"])),
                "time_slot": time_slot or _hour_to_slot(target_datetime.hour),
                "weather_type": weather_type or DEFAULT_ROW["weather_type"],
                "temperature": temperature or DEFAULT_ROW["temperature"],
                "target_datetime": target_datetime.isoformat(),
            },
            log_request=log_request,
            source="demand_dashboard",
        )
        rows.append(prediction)

    rows.sort(key=lambda item: item["predicted_demand"], reverse=True)
    total_predicted = sum(item["predicted_demand"] for item in rows)
    total_preparation = sum(item["suggested_preparation"] for item in rows)
    average_confidence = round(
        float(np.mean([item["confidence_score"] for item in rows])) if rows else 0.0,
        2,
    )
    low_confidence_items = [
        item["food_item"] for item in rows if item["confidence_label"] == "Low"
    ]

    return {
        "dashboard": rows,
        "summary": {
            "items_forecasted": len(rows),
            "active_menu_items": len(menu_rows),
            "total_predicted_demand": total_predicted,
            "total_suggested_preparation": total_preparation,
            "estimated_total_waste": max(total_preparation - total_predicted, 0),
            "average_confidence": average_confidence,
            "highest_demand_item": rows[0]["food_item"] if rows else "N/A",
            "low_confidence_count": len(low_confidence_items),
            "target_date": target_datetime.strftime("%Y-%m-%d"),
            "generated_at": datetime.now().isoformat(),
            "time_slot": time_slot or _hour_to_slot(target_datetime.hour),
        },
        "low_confidence_items": low_confidence_items,
        "menu_basis": {
            "source": "active_menu",
            "items": [
                {
                    "id": str(item.get("id") or _normalize_food_name(item.get("name"))),
                    "name": str(item.get("name", "")).strip(),
                    "category": str(item.get("category", "general")).strip().lower() or "general",
                    "price": int(item.get("price", 0) or 0),
                }
                for item in menu_rows
                if str(item.get("name", "")).strip()
            ],
        },
        "formula": "Predicted demand is the confidence-adjusted forecast. Suggested preparation adds a bounded safety buffer based on confidence, volatility, and trend.",
        "example": "If predicted demand is 180 and the buffer is 15%, the suggested preparation is about 207 portions.",
        "model": {
            "name": load_model_bundle().get("best_model_name", "Heuristic fallback"),
            "trained_at": get_training_metrics().get("trained_at"),
        },
    }


def generate_forecast_rows(days_ahead: int = 1) -> list[dict[str, Any]]:
    target_datetime = datetime.now() + timedelta(days=days_ahead)
    dashboard = build_demand_dashboard(
        target_datetime=target_datetime,
        time_slot="11:00-13:00",
        log_request=True,
    )
    rows = []
    for item in dashboard["dashboard"]:
        rows.append(
            {
                "target_date": item["target_date"],
                "time_slot": item["time_slot"],
                "food_item": item["food_item"],
                "predicted_demand": item["predicted_demand"],
                "suggested_preparation": item["suggested_preparation"],
                "confidence_score": item["confidence_score"],
                "confidence_label": item["confidence_label"],
                "recommended_action": item["recommended_action"],
            }
        )
    if rows:
        pd.DataFrame(rows).to_csv(FORECAST_OUTPUT_PATH, index=False)
    return rows


def get_training_metrics() -> dict[str, Any]:
    return _safe_read_json(TRAINING_METRICS_PATH, {})


def _prediction_key(log: dict[str, Any]) -> str:
    food = _normalize_food_name(log.get("food_item"))
    target_date = str(log.get("target_date", "")).strip()
    time_slot = str(log.get("time_slot", "")).strip()
    source = str(log.get("source", "")).strip()
    return f"{source}|{target_date}|{time_slot}|{food}"


def resolve_prediction_logs() -> list[dict[str, Any]]:
    rows = _safe_read_prediction_logs()
    if not rows:
        return []

    orders_df = _safe_read_orders()
    operations_df = _safe_read_operations()
    today_key = datetime.now().strftime("%Y-%m-%d")
    resolved_rows = []

    for row in rows:
        resolved = dict(row)
        target_date = str(resolved.get("target_date", "")).strip()
        time_slot = str(resolved.get("time_slot", "")).strip()
        food_item = _normalize_food_name(resolved.get("food_item"))

        actual_sold = resolved.get("actual_sold")
        if actual_sold in (None, "", "null"):
            actual_value = None
            if not operations_df.empty and target_date and time_slot and food_item:
                matches = operations_df[
                    (operations_df["date"] == target_date)
                    & (operations_df["time_slot"] == time_slot)
                    & (operations_df["food_item"].astype(str).str.lower() == food_item)
                ]
                if not matches.empty:
                    actual_value = int(matches["quantity_sold"].sum())
                elif target_date < today_key:
                    actual_value = 0
            elif not orders_df.empty and target_date and time_slot and food_item:
                matches = orders_df[
                    (orders_df["date"] == target_date)
                    & (orders_df["time_slot"] == time_slot)
                    & (orders_df["food_item"].astype(str).str.lower() == food_item)
                ]
                if not matches.empty:
                    actual_value = int(matches["quantity"].sum())
                elif target_date < today_key:
                    actual_value = 0
            resolved["actual_sold"] = actual_value

        if target_date and time_slot and food_item and not operations_df.empty:
            matches = operations_df[
                (operations_df["date"] == target_date)
                & (operations_df["time_slot"] == time_slot)
                & (operations_df["food_item"].astype(str).str.lower() == food_item)
            ]
            if not matches.empty:
                if resolved.get("actual_prepared") in (None, "", "null"):
                    resolved["actual_prepared"] = int(matches["quantity_prepared"].sum())
                if resolved.get("actual_wasted") in (None, "", "null"):
                    resolved["actual_wasted"] = int(matches["quantity_wasted"].sum())

        if (
            resolved.get("actual_wasted") in (None, "", "null")
            and resolved.get("actual_prepared") not in (None, "", "null")
            and resolved.get("actual_sold") not in (None, "", "null")
        ):
            resolved["actual_wasted"] = max(
                int(resolved.get("actual_prepared") or 0) - int(resolved.get("actual_sold") or 0),
                0,
            )

        predicted = float(resolved.get("predicted_demand") or 0)
        actual_value = resolved.get("actual_sold")
        if actual_value is None:
            resolved["accuracy_percentage"] = None
        else:
            denominator = max(predicted, float(actual_value), 1.0)
            accuracy = (1 - abs(predicted - float(actual_value)) / denominator) * 100
            resolved["accuracy_percentage"] = round(max(0.0, accuracy), 2)
        resolved_rows.append(resolved)

    resolved_rows.sort(
        key=lambda item: (
            str(item.get("target_date", "")),
            str(item.get("time_slot", "")),
            str(item.get("logged_at", "")),
        ),
        reverse=True,
    )
    return resolved_rows


def compute_prediction_accuracy_summary(top_n: int = 5) -> dict[str, Any]:
    logs = resolve_prediction_logs()
    if not logs:
        return {
            "overall_accuracy_percentage": 0.0,
            "total_predictions": 0,
            "resolved_predictions": 0,
            "pending_predictions": 0,
            "recent_logs": [],
            "accuracy_by_food": [],
            "note": "No prediction logs available yet.",
        }

    resolved_logs = [log for log in logs if log.get("actual_sold") is not None]
    pending_logs = [log for log in logs if log.get("actual_sold") is None]

    if not resolved_logs:
        return {
            "overall_accuracy_percentage": 0.0,
            "total_predictions": len(logs),
            "resolved_predictions": 0,
            "pending_predictions": len(pending_logs),
            "recent_logs": pending_logs[:top_n],
            "accuracy_by_food": [],
            "note": "Predictions have been logged, but actual sales are still pending.",
        }

    accuracy_frame = pd.DataFrame(resolved_logs)
    grouped = (
        accuracy_frame.groupby("food_item", dropna=False)
        .agg(
            predicted_average=("predicted_demand", "mean"),
            actual_average=("actual_sold", "mean"),
            accuracy_percentage=("accuracy_percentage", "mean"),
        )
        .sort_values(by="accuracy_percentage", ascending=False)
        .reset_index()
    )

    accuracy_by_food = []
    for _, row in grouped.head(top_n).iterrows():
        accuracy_by_food.append(
            {
                "food_item": str(row["food_item"]),
                "predicted_average": round(float(row["predicted_average"]), 2),
                "actual_average": round(float(row["actual_average"]), 2),
                "accuracy_percentage": round(float(row["accuracy_percentage"]), 2),
            }
        )

    return {
        "overall_accuracy_percentage": round(
            float(accuracy_frame["accuracy_percentage"].mean()), 2
        ),
        "total_predictions": len(logs),
        "resolved_predictions": len(resolved_logs),
        "pending_predictions": len(pending_logs),
        "recent_logs": logs[:top_n],
        "accuracy_by_food": accuracy_by_food,
    }


def compute_waste_summary() -> dict[str, Any]:
    logs = resolve_prediction_logs()
    resolved_logs = [log for log in logs if log.get("actual_sold") is not None]
    if resolved_logs:
        item_totals: dict[str, dict[str, Any]] = {}
        for log in resolved_logs:
            food_item = str(log.get("food_item") or "Unknown")
            actual_sold = int(log.get("actual_sold") or 0)
            actual_prepared = int(log.get("actual_prepared") or log.get("suggested_preparation") or 0)
            actual_wasted = (
                int(log.get("actual_wasted"))
                if log.get("actual_wasted") not in (None, "", "null")
                else max(actual_prepared - actual_sold, 0)
            )
            baseline_prepared_for_item = max(
                int(log.get("historical_preparation_average") or log.get("suggested_preparation") or 0),
                actual_sold,
            )
            entry = item_totals.setdefault(
                food_item,
                {
                    "food_item": food_item,
                    "prepared": 0,
                    "sold": 0,
                    "wasted": 0,
                    "baseline_waste": 0,
                    "saved_units": 0,
                },
            )
            entry["prepared"] += actual_prepared
            entry["sold"] += actual_sold
            entry["wasted"] += actual_wasted
            entry["baseline_waste"] += max(baseline_prepared_for_item - actual_sold, 0)

        item_breakdown = []
        for entry in item_totals.values():
            entry["saved_units"] = max(entry["baseline_waste"] - entry["wasted"], 0)
            entry["waste_percentage"] = round(
                (entry["wasted"] / entry["prepared"] * 100) if entry["prepared"] else 0.0,
                2,
            )
            item_breakdown.append(entry)
        item_breakdown.sort(key=lambda item: item["wasted"], reverse=True)

        total_prepared = sum(
            int(log.get("actual_prepared") or log.get("suggested_preparation") or 0)
            for log in resolved_logs
        )
        total_sold = sum(int(log.get("actual_sold") or 0) for log in resolved_logs)
        total_wasted = sum(
            int(
                log.get("actual_wasted")
                if log.get("actual_wasted") not in (None, "", "null")
                else max(
                    int(log.get("actual_prepared") or log.get("suggested_preparation") or 0)
                    - int(log.get("actual_sold") or 0),
                    0,
                )
            )
            for log in resolved_logs
        )

        baseline_prepared = sum(
            max(
                int(log.get("historical_preparation_average") or log.get("suggested_preparation") or 0),
                int(log.get("actual_sold") or 0),
            )
            for log in resolved_logs
        )
        baseline_waste = max(baseline_prepared - total_sold, 0)
        estimated_reduction = max(baseline_waste - total_wasted, 0)
        waste_percentage = (total_wasted / total_prepared * 100) if total_prepared else 0.0
        sell_through_percentage = (total_sold / total_prepared * 100) if total_prepared else 0.0
        return {
            "total_food_prepared": int(total_prepared),
            "total_food_sold": int(total_sold),
            "total_food_wasted": int(total_wasted),
            "waste_percentage": round(float(waste_percentage), 2),
            "sell_through_percentage": round(float(sell_through_percentage), 2),
            "estimated_waste_after_ml": int(total_wasted),
            "estimated_reduction": int(estimated_reduction),
            "baseline_waste": int(baseline_waste),
            "prediction_count_used": len(resolved_logs),
            "item_waste_breakdown": item_breakdown[:10],
            "note": "Waste summary is based on canteen preparation logs matched with ML recommendations and actual sales.",
        }

    dataset_df = _safe_read_dataset()
    if dataset_df.empty:
        return {
            "total_food_prepared": 0,
            "total_food_sold": 0,
            "total_food_wasted": 0,
            "waste_percentage": 0.0,
            "estimated_waste_after_ml": 0,
            "estimated_reduction": 0,
            "baseline_waste": 0,
            "prediction_count_used": 0,
            "note": "No resolved prediction logs or dataset rows are available yet.",
        }

    dashboard = build_demand_dashboard(log_request=False)
    dashboard_rows = dashboard.get("dashboard", [])
    if dashboard_rows:
        item_breakdown = []
        for row in dashboard_rows:
            prepared = int(row.get("suggested_preparation") or 0)
            sold = int(round(float(row.get("expected_demand_anchor") or row.get("predicted_demand") or 0)))
            wasted = int(row.get("expected_waste") or max(prepared - sold, 0))
            historical_prepared = int(row.get("historical_preparation_average") or prepared)
            baseline_waste = max(historical_prepared - sold, 0)
            item_breakdown.append(
                {
                    "food_item": row.get("food_item", "Unknown"),
                    "prepared": prepared,
                    "sold": sold,
                    "wasted": wasted,
                    "waste_percentage": round((wasted / prepared * 100) if prepared else 0.0, 2),
                    "baseline_waste": baseline_waste,
                    "saved_units": max(baseline_waste - wasted, 0),
                }
            )
        item_breakdown.sort(key=lambda item: item["wasted"], reverse=True)

        total_prepared = sum(int(row.get("suggested_preparation") or 0) for row in dashboard_rows)
        total_sold = sum(int(round(float(row.get("expected_demand_anchor") or row.get("predicted_demand") or 0))) for row in dashboard_rows)
        total_wasted = sum(int(row.get("expected_waste") or 0) for row in dashboard_rows)
        baseline_waste = sum(
            max(
                int(row.get("historical_preparation_average") or row.get("suggested_preparation") or 0)
                - int(round(float(row.get("expected_demand_anchor") or row.get("predicted_demand") or 0))),
                0,
            )
            for row in dashboard_rows
        )
        estimated_reduction = max(baseline_waste - total_wasted, 0)
        waste_percentage = (total_wasted / total_prepared * 100) if total_prepared else 0.0
        sell_through_percentage = (total_sold / total_prepared * 100) if total_prepared else 0.0
        return {
            "total_food_prepared": int(total_prepared),
            "total_food_sold": int(total_sold),
            "total_food_wasted": int(total_wasted),
            "waste_percentage": round(float(waste_percentage), 2),
            "sell_through_percentage": round(float(sell_through_percentage), 2),
            "estimated_waste_after_ml": int(total_wasted),
            "estimated_reduction": int(estimated_reduction),
            "baseline_waste": int(baseline_waste),
            "prediction_count_used": 0,
            "item_waste_breakdown": item_breakdown[:10],
            "note": "Waste summary is currently forecast-based because resolved canteen actuals are still limited.",
        }

    item_breakdown = []
    if not dataset_df.empty and {"food_item", "quantity_prepared", TARGET_COLUMN, "quantity_wasted"}.issubset(dataset_df.columns):
        grouped = (
            dataset_df.groupby("food_item", dropna=False)
            .agg(
                prepared=("quantity_prepared", "sum"),
                sold=(TARGET_COLUMN, "sum"),
                wasted=("quantity_wasted", "sum"),
            )
            .reset_index()
        )
        for _, row in grouped.iterrows():
            prepared = int(row["prepared"] or 0)
            sold = int(row["sold"] or 0)
            wasted = int(row["wasted"] or 0)
            item_breakdown.append(
                {
                    "food_item": str(row["food_item"] or "Unknown"),
                    "prepared": prepared,
                    "sold": sold,
                    "wasted": wasted,
                    "waste_percentage": round((wasted / prepared * 100) if prepared else 0.0, 2),
                    "baseline_waste": wasted,
                    "saved_units": 0,
                }
            )
        item_breakdown.sort(key=lambda item: item["wasted"], reverse=True)

    total_prepared = int(pd.to_numeric(dataset_df["quantity_prepared"], errors="coerce").fillna(0).sum())
    total_sold = int(pd.to_numeric(dataset_df[TARGET_COLUMN], errors="coerce").fillna(0).sum())
    total_wasted = int(pd.to_numeric(dataset_df["quantity_wasted"], errors="coerce").fillna(0).sum())
    waste_percentage = (total_wasted / total_prepared * 100) if total_prepared else 0.0
    sell_through_percentage = (total_sold / total_prepared * 100) if total_prepared else 0.0
    estimated_reduction = int(round(total_wasted * 0.15))
    return {
        "total_food_prepared": total_prepared,
        "total_food_sold": total_sold,
        "total_food_wasted": total_wasted,
        "waste_percentage": round(float(waste_percentage), 2),
        "sell_through_percentage": round(float(sell_through_percentage), 2),
        "estimated_waste_after_ml": max(total_wasted - estimated_reduction, 0),
        "estimated_reduction": estimated_reduction,
        "baseline_waste": total_wasted,
        "prediction_count_used": 0,
        "item_waste_breakdown": item_breakdown[:10],
        "note": "Waste summary is currently using the historical dataset because live resolved predictions are not available yet.",
    }


def _format_trend_label(value: Any) -> str:
    parsed = pd.to_datetime(value, errors="coerce")
    if pd.isna(parsed):
        return str(value or "N/A")
    return parsed.strftime("%d %b")


def build_predicted_vs_actual_trend(limit: int = 7) -> list[dict[str, Any]]:
    resolved_logs = [
        log for log in resolve_prediction_logs() if log.get("actual_sold") is not None
    ]
    if not resolved_logs:
        return []

    frame = pd.DataFrame(
        [
            {
                "target_date": log.get("target_date"),
                "predicted_total": float(log.get("predicted_demand") or 0),
                "actual_total": float(log.get("actual_sold") or 0),
            }
            for log in resolved_logs
        ]
    )
    if frame.empty:
        return []

    grouped = (
        frame.groupby("target_date", dropna=False)
        .agg(
            predicted_total=("predicted_total", "sum"),
            actual_total=("actual_total", "sum"),
        )
        .reset_index()
        .sort_values(by="target_date")
        .tail(limit)
    )

    return [
        {
            "label": _format_trend_label(row["target_date"]),
            "target_date": str(row["target_date"]),
            "predicted_total": int(round(float(row["predicted_total"]))),
            "actual_total": int(round(float(row["actual_total"]))),
        }
        for _, row in grouped.iterrows()
    ]


def build_confidence_trend(limit: int = 7) -> list[dict[str, Any]]:
    logs = resolve_prediction_logs()
    if not logs:
        return []

    frame = pd.DataFrame(
        [
            {
                "target_date": log.get("target_date"),
                "confidence_score": float(log.get("confidence_score") or 0),
            }
            for log in logs
            if log.get("target_date")
        ]
    )
    if frame.empty:
        return []

    grouped = (
        frame.groupby("target_date", dropna=False)
        .agg(
            average_confidence=("confidence_score", "mean"),
            sample_count=("confidence_score", "count"),
        )
        .reset_index()
        .sort_values(by="target_date")
        .tail(limit)
    )

    return [
        {
            "label": _format_trend_label(row["target_date"]),
            "target_date": str(row["target_date"]),
            "average_confidence": round(float(row["average_confidence"]), 2),
            "sample_count": int(row["sample_count"]),
        }
        for _, row in grouped.iterrows()
    ]


def build_waste_reduction_trend(limit: int = 7) -> list[dict[str, Any]]:
    resolved_logs = [
        log for log in resolve_prediction_logs() if log.get("actual_sold") is not None
    ]
    if not resolved_logs:
        return []

    rows = []
    for log in resolved_logs:
        actual_sold = int(log.get("actual_sold") or 0)
        actual_prepared = int(
            log.get("actual_prepared") or log.get("suggested_preparation") or 0
        )
        actual_wasted = (
            int(log.get("actual_wasted"))
            if log.get("actual_wasted") not in (None, "", "null")
            else max(actual_prepared - actual_sold, 0)
        )
        baseline_prepared = max(
            int(
                log.get("historical_preparation_average")
                or log.get("suggested_preparation")
                or 0
            ),
            actual_sold,
        )
        baseline_waste = max(baseline_prepared - actual_sold, 0)
        rows.append(
            {
                "target_date": log.get("target_date"),
                "baseline_waste": baseline_waste,
                "actual_waste": actual_wasted,
                "saved_units": max(baseline_waste - actual_wasted, 0),
            }
        )

    frame = pd.DataFrame(rows)
    if frame.empty:
        return []

    grouped = (
        frame.groupby("target_date", dropna=False)
        .agg(
            baseline_waste=("baseline_waste", "sum"),
            actual_waste=("actual_waste", "sum"),
            saved_units=("saved_units", "sum"),
        )
        .reset_index()
        .sort_values(by="target_date")
        .tail(limit)
    )

    return [
        {
            "label": _format_trend_label(row["target_date"]),
            "target_date": str(row["target_date"]),
            "baseline_waste": int(round(float(row["baseline_waste"]))),
            "actual_waste": int(round(float(row["actual_waste"]))),
            "saved_units": int(round(float(row["saved_units"]))),
        }
        for _, row in grouped.iterrows()
    ]


def build_ml_system_overview() -> dict[str, Any]:
    training_metrics = get_training_metrics()
    training_status = get_training_status()
    demand = build_demand_dashboard(log_request=False)
    accuracy = compute_prediction_accuracy_summary()
    waste = compute_waste_summary()
    demand_summary = demand.get("summary", {})
    top_recommendations = demand.get("dashboard", [])[:3]
    low_confidence_items = [
        item for item in demand.get("dashboard", []) if item.get("confidence_label") == "Low"
    ]

    total_predictions = int(accuracy.get("total_predictions", 0) or 0)
    resolved_predictions = int(accuracy.get("resolved_predictions", 0) or 0)
    pending_predictions = int(accuracy.get("pending_predictions", 0) or 0)
    overall_accuracy = float(accuracy.get("overall_accuracy_percentage", 0.0) or 0.0)

    items_forecasted = int(demand_summary.get("items_forecasted", 0) or 0)
    active_menu_items = int(demand_summary.get("active_menu_items", items_forecasted) or items_forecasted)
    low_confidence_count = int(demand_summary.get("low_confidence_count", len(low_confidence_items)) or len(low_confidence_items))

    baseline_waste = int(waste.get("baseline_waste", 0) or 0)
    estimated_reduction = int(waste.get("estimated_reduction", 0) or 0)
    after_ml_waste = int(waste.get("estimated_waste_after_ml", 0) or 0)
    prediction_count_used = int(waste.get("prediction_count_used", 0) or 0)

    forecast_coverage_percentage = round(
        (items_forecasted / active_menu_items * 100) if active_menu_items else 0.0,
        2,
    )
    resolved_prediction_rate = round(
        (resolved_predictions / total_predictions * 100) if total_predictions else 0.0,
        2,
    )
    low_confidence_rate = round(
        (low_confidence_count / items_forecasted * 100) if items_forecasted else 0.0,
        2,
    )
    waste_reduction_percentage = round(
        (estimated_reduction / baseline_waste * 100) if baseline_waste else 0.0,
        2,
    )

    best_r2 = float(training_metrics.get("best_r2", 0.0) or 0.0)
    if best_r2 >= 0.75:
        model_health = "Strong"
    elif best_r2 >= 0.55:
        model_health = "Promising"
    elif best_r2 > 0:
        model_health = "Early-stage"
    else:
        model_health = "Not trained"

    if low_confidence_rate <= 35 and resolved_prediction_rate >= 60:
        data_readiness = "Operationally reliable"
    elif resolved_prediction_rate >= 25:
        data_readiness = "Improving with live data"
    else:
        data_readiness = "Needs more live canteen logs"

    operator_actions: list[str] = []
    if active_menu_items and items_forecasted < active_menu_items:
        operator_actions.append(
            f"Forecast coverage is {items_forecasted}/{active_menu_items}; sync missing active menu items before service."
        )
    if low_confidence_rate >= 50:
        operator_actions.append(
            "Many forecasts are low-confidence; log prepared, sold, and wasted values daily to strengthen live signals."
        )
    if resolved_prediction_rate < 40:
        operator_actions.append(
            "Only a small share of predictions have matched actuals; complete end-of-slot operations logs more consistently."
        )
    if baseline_waste and estimated_reduction <= 0:
        operator_actions.append(
            "Waste impact is not visible yet; compare suggested prep against actual prepared quantities for each slot."
        )
    if not operator_actions:
        operator_actions.append(
            "The ML loop is healthy right now; keep logging operations so accuracy and waste tracking stay current."
        )

    low_confidence_breakdown = {
        "limited_history": 0,
        "weak_same_slot_history": 0,
        "other": 0,
    }
    for item in low_confidence_items:
        snapshot = item.get("feature_snapshot") or {}
        history_points = int(snapshot.get("history_points", 0) or 0)
        same_slot_points = int(snapshot.get("same_slot_points", 0) or 0)
        if history_points < 3:
            low_confidence_breakdown["limited_history"] += 1
        elif same_slot_points < 2:
            low_confidence_breakdown["weak_same_slot_history"] += 1
        else:
            low_confidence_breakdown["other"] += 1

    predicted_vs_actual_trend = build_predicted_vs_actual_trend()
    waste_reduction_trend = build_waste_reduction_trend()
    confidence_trend = build_confidence_trend()

    return {
        "training": training_metrics,
        "training_status": training_status,
        "demand_summary": demand_summary,
        "top_recommendations": top_recommendations,
        "low_confidence_items": low_confidence_items,
        "accuracy_summary": {
            "overall_accuracy_percentage": overall_accuracy,
            "pending_predictions": pending_predictions,
            "resolved_predictions": resolved_predictions,
            "total_predictions": total_predictions,
            "resolved_prediction_rate": resolved_prediction_rate,
        },
        "waste_summary": waste,
        "impact_summary": {
            "model_health": model_health,
            "data_readiness": data_readiness,
            "forecast_coverage_percentage": forecast_coverage_percentage,
            "resolved_prediction_rate": resolved_prediction_rate,
            "low_confidence_rate": low_confidence_rate,
            "waste_reduction_percentage": waste_reduction_percentage,
            "waste_saved_units": estimated_reduction,
            "baseline_waste": baseline_waste,
            "waste_after_ml": after_ml_waste,
            "prediction_count_used": prediction_count_used,
            "headline": (
                f"ML currently covers {items_forecasted}/{active_menu_items or items_forecasted} active menu items, "
                f"has matched {resolved_predictions}/{total_predictions or max(resolved_predictions, 1)} predictions with actuals, "
                f"and is tracking {estimated_reduction} units of estimated waste reduction versus baseline."
            ),
        },
        "operator_actions": operator_actions,
        "confidence_breakdown": low_confidence_breakdown,
        "trends": {
            "predicted_vs_actual": predicted_vs_actual_trend,
            "waste_reduction": waste_reduction_trend,
            "confidence": confidence_trend,
        },
    }
