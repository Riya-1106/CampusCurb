import json
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

from ml_pipeline import compute_waste_summary, resolve_prediction_logs


BASE_DIR = Path(__file__).resolve().parent
MODELS_DIR = BASE_DIR / "models"
DATA_DIR = BASE_DIR / "data"

DATASET_PATH = MODELS_DIR / "food_demand_dataset.csv"
METRICS_PATH = DATA_DIR / "ml_training_metrics.json"
PREDICTION_LOGS_PATH = DATA_DIR / "prediction_logs.json"

MODELS_DIR.mkdir(parents=True, exist_ok=True)


def load_json(path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text())
    except Exception:
        return default


def create_placeholder_chart(title, message, output_path):
    plt.figure(figsize=(10, 5))
    plt.text(0.5, 0.5, message, ha="center", va="center", fontsize=12)
    plt.title(title)
    plt.axis("off")
    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close()


# =====================================================
# GRAPH 1 : ACTUAL VS PREDICTED DEMAND
# =====================================================

def graph_actual_vs_predicted():
    logs = load_json(PREDICTION_LOGS_PATH, [])
    resolved = [
        row for row in logs
        if row.get("actual_sold") not in (None, "", "null")
    ]

    output_path = MODELS_DIR / "actual_vs_predicted_demand.png"

    if not resolved:
        create_placeholder_chart(
            "Actual vs Predicted Demand",
            "No resolved prediction logs with actual_sold found.",
            output_path,
        )
        return

    df = pd.DataFrame(resolved)
    df["target_date"] = pd.to_datetime(df["target_date"], errors="coerce")
    df = df.dropna(subset=["target_date"])
    df["predicted_demand"] = pd.to_numeric(df["predicted_demand"], errors="coerce").fillna(0)
    df["actual_sold"] = pd.to_numeric(df["actual_sold"], errors="coerce").fillna(0)

    grouped = (
        df.groupby("target_date", as_index=False)[["predicted_demand", "actual_sold"]]
        .sum()
        .sort_values("target_date")
    )

    plt.figure(figsize=(12, 6))
    plt.plot(grouped["target_date"], grouped["actual_sold"], marker="o", linewidth=2, label="Actual Quantity Sold")
    plt.plot(grouped["target_date"], grouped["predicted_demand"], marker="o", linewidth=2, label="Predicted Demand")
    plt.title("Actual vs Predicted Demand")
    plt.xlabel("Date")
    plt.ylabel("Quantity")
    plt.legend()
    plt.grid(True, linestyle="--", alpha=0.4)
    plt.xticks(rotation=45)
    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close()


# =====================================================
# GRAPH 2 : MODEL COMPARISON
# =====================================================

def graph_model_comparison():
    metrics = load_json(METRICS_PATH, {})
    models = metrics.get("models", {})
    output_path = MODELS_DIR / "model_comparison.png"

    if not models:
        create_placeholder_chart(
            "Model Comparison",
            "No model metrics found in ml_training_metrics.json.",
            output_path,
        )
        return

    model_names = list(models.keys())
    r2_scores = [models[name].get("r2", 0) for name in model_names]
    mae_scores = [models[name].get("mae", 0) for name in model_names]
    mse_scores = [models[name].get("mse", 0) for name in model_names]

    fig, axes = plt.subplots(1, 3, figsize=(18, 5))

    axes[0].bar(model_names, r2_scores, color="steelblue")
    axes[0].set_title("R2 Score Comparison")
    axes[0].set_ylabel("R2 Score")
    axes[0].tick_params(axis="x", rotation=20)

    axes[1].bar(model_names, mae_scores, color="darkorange")
    axes[1].set_title("MAE Comparison")
    axes[1].set_ylabel("MAE")
    axes[1].tick_params(axis="x", rotation=20)

    axes[2].bar(model_names, mse_scores, color="seagreen")
    axes[2].set_title("MSE Comparison")
    axes[2].set_ylabel("MSE")
    axes[2].tick_params(axis="x", rotation=20)

    fig.suptitle("Model Performance Comparison", fontsize=14)
    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close()


# =====================================================
# GRAPH 3 : QUANTITY SOLD DISTRIBUTION
# =====================================================

def graph_quantity_sold_distribution():
    output_path = MODELS_DIR / "quantity_sold_distribution.png"

    if not DATASET_PATH.exists():
        create_placeholder_chart(
            "Distribution of Quantity Sold",
            "Dataset file food_demand_dataset.csv not found.",
            output_path,
        )
        return

    df = pd.read_csv(DATASET_PATH)
    if "quantity_sold" not in df.columns:
        create_placeholder_chart(
            "Distribution of Quantity Sold",
            "Column quantity_sold not found in dataset.",
            output_path,
        )
        return

    quantity_sold = pd.to_numeric(df["quantity_sold"], errors="coerce").dropna()

    plt.figure(figsize=(10, 6))
    plt.hist(quantity_sold, bins=20, color="mediumpurple", edgecolor="black", alpha=0.8)
    plt.title("Distribution of Quantity Sold")
    plt.xlabel("Quantity Sold")
    plt.ylabel("Frequency")
    plt.grid(axis="y", linestyle="--", alpha=0.4)
    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close()


# =====================================================
# GRAPH 4 : FOOD ITEM DEMAND DISTRIBUTION
# =====================================================

def graph_food_item_demand_distribution():
    output_path = MODELS_DIR / "food_item_demand_distribution.png"

    if not DATASET_PATH.exists():
        create_placeholder_chart(
            "Food Item Demand Distribution",
            "Dataset file food_demand_dataset.csv not found.",
            output_path,
        )
        return

    df = pd.read_csv(DATASET_PATH)
    if "food_item" not in df.columns or "quantity_sold" not in df.columns:
        create_placeholder_chart(
            "Food Item Demand Distribution",
            "Required columns food_item / quantity_sold not found.",
            output_path,
        )
        return

    df["quantity_sold"] = pd.to_numeric(df["quantity_sold"], errors="coerce").fillna(0)

    grouped = (
        df.groupby("food_item", as_index=False)["quantity_sold"]
        .mean()
        .sort_values("quantity_sold", ascending=False)
    )

    plt.figure(figsize=(12, 6))
    plt.bar(grouped["food_item"], grouped["quantity_sold"], color="teal")
    plt.title("Average Quantity Sold per Food Item")
    plt.xlabel("Food Item")
    plt.ylabel("Average Quantity Sold")
    plt.xticks(rotation=30, ha="right")
    plt.grid(axis="y", linestyle="--", alpha=0.4)
    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close()


# =====================================================
# GRAPH 5 : WASTE REDUCTION ANALYSIS
# =====================================================

def graph_waste_reduction():
    output_path = MODELS_DIR / "waste_reduction.png"
    summary = compute_waste_summary()

    baseline_waste = int(summary.get("baseline_waste", 0) or 0)
    after_ml_waste = int(summary.get("estimated_waste_after_ml", 0) or 0)
    reduction = int(summary.get("estimated_reduction", 0) or 0)

    if baseline_waste == 0 and after_ml_waste == 0 and reduction == 0:
        resolved_logs = resolve_prediction_logs()
        if not resolved_logs:
            create_placeholder_chart(
                "Waste Reduction Analysis",
                "Not enough resolved waste data is available yet.",
                output_path,
            )
            return

    labels = ["Baseline Waste", "Waste After ML", "Waste Reduced"]
    values = [baseline_waste, after_ml_waste, reduction]
    colors = ["indianred", "goldenrod", "seagreen"]

    plt.figure(figsize=(10, 6))
    bars = plt.bar(labels, values, color=colors)
    plt.title("Waste Reduction Analysis")
    plt.ylabel("Food Units")
    plt.grid(axis="y", linestyle="--", alpha=0.4)

    for bar, value in zip(bars, values):
        plt.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + max(values) * 0.02 if max(values) > 0 else 0.5,
            str(value),
            ha="center",
            va="bottom",
            fontsize=10,
        )

    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close()


def main():
    graph_actual_vs_predicted()
    graph_model_comparison()
    graph_quantity_sold_distribution()
    graph_food_item_demand_distribution()
    graph_waste_reduction()

    print("Graphs generated successfully in:", MODELS_DIR)
    print("1. actual_vs_predicted_demand.png")
    print("2. model_comparison.png")
    print("3. quantity_sold_distribution.png")
    print("4. food_item_demand_distribution.png")
    print("5. waste_reduction.png")


if __name__ == "__main__":
    main()
