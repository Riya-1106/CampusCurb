import pandas as pd
import os

def waste_analysis():

    dataset_path = "models/food_demand_dataset.csv"

    if not os.path.exists(dataset_path):
        # Dataset not available yet; return a strong sample report for demonstration
        return {
            "total_food_prepared": 5000,
            "total_food_sold": 4200,
            "total_food_wasted": 800,
            "waste_percentage": 16.0,
            "estimated_waste_after_ml": 680,
            "estimated_reduction": 120,
            "note": "Dataset not found; returning sample report values."
        }

    df = pd.read_csv(dataset_path)

    total_prepared = df["quantity_prepared"].sum()
    total_sold = df["quantity_sold"].sum()
    total_wasted = df["quantity_wasted"].sum()

    if total_prepared == 0:
        waste_percentage = 0
    else:
        waste_percentage = (total_wasted / total_prepared) * 100

    # Estimated ML waste reduction (15%)
    estimated_reduction = total_wasted * 0.15
    new_waste = total_wasted - estimated_reduction

    return {

        "total_food_prepared": int(total_prepared),
        "total_food_sold": int(total_sold),
        "total_food_wasted": int(total_wasted),

        "waste_percentage": round(waste_percentage,2),

        "estimated_waste_after_ml": int(new_waste),
        "estimated_reduction": int(estimated_reduction)

    }