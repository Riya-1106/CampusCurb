import pandas as pd

def waste_analysis():

    # Load dataset
    df = pd.read_csv("models/food_demand_dataset.csv")

    total_prepared = df["quantity_prepared"].sum()
    total_sold = df["quantity_sold"].sum()
    total_wasted = df["quantity_wasted"].sum()

    waste_percentage = (total_wasted / total_prepared) * 100

    # Estimate ML waste reduction
    # assume ML reduces over-preparation by 15%
    estimated_reduction = total_wasted * 0.15

    new_waste = total_wasted - estimated_reduction

    return {

        "total_food_prepared": int(total_prepared),
        "total_food_sold": int(total_sold),
        "total_food_wasted": int(total_wasted),
        "waste_percentage": round(waste_percentage, 2),

        "estimated_waste_after_ml": int(new_waste),
        "estimated_reduction": int(estimated_reduction)

    }