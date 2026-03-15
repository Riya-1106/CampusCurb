import joblib
import pandas as pd

from log_prediction import log_prediction

# ==========================================
# LOAD TRAINED MODEL
# ==========================================

model = None
dataset = None

try:
    model = joblib.load("models/best_model.pkl")
except FileNotFoundError:
    print("Warning: models/best_model.pkl not found. Using fallback predictions.")

try:
    dataset = pd.read_csv("models/food_demand_dataset.csv")
except FileNotFoundError:
    print("Warning: models/food_demand_dataset.csv not found. Some features will be limited.")

# ==========================================
# PREPARE ENCODING REFERENCES
# ==========================================

if dataset is not None:
    food_items = list(dataset["food_item"].unique())
    food_categories = list(dataset["food_category"].unique())
    time_slots = list(dataset["time_slot"].unique())
    weather_types = list(dataset["weather_type"].unique())
else:
    food_items = []
    food_categories = []
    time_slots = []
    weather_types = []


# ==========================================
# PREDICTION FUNCTION
# ==========================================

def predict_demand(input_data: dict):

    """
    input_data example:

    {
        "food_item": "Burger",
        "time_slot": "11:00-13:00",
        "weather_type": "Rainy",
        "price": 80
    }

    """

    # ---------------------------------------
    # CONVERT CATEGORICAL VALUES
    # ---------------------------------------

    # If the dataset is missing or the value is unknown, fall back to 0
    food_value = input_data.get("food_item")
    time_value = input_data.get("time_slot")
    weather_value = input_data.get("weather_type")

    food_item = food_items.index(food_value) if (food_value in food_items) else 0
    time_slot = time_slots.index(time_value) if (time_value in time_slots) else 0
    weather = weather_types.index(weather_value) if (weather_value in weather_types) else 0

    # ---------------------------------------
    # BUILD MODEL INPUT ROW
    # ---------------------------------------

    row = {

        "day_of_week": input_data.get("day_of_week", 2),
        "week_of_year": input_data.get("week_of_year", 10),
        "month": input_data.get("month", 3),

        "time_slot": time_slot,
        "is_weekend": input_data.get("is_weekend", 0),
        "is_holiday": input_data.get("is_holiday", 0),
        "is_exam_day": input_data.get("is_exam_day", 0),

        "food_item": food_item,
        "food_category": 0,

        "is_veg": input_data.get("is_veg", 1),
        "price": input_data.get("price", 80),
        "portion_size": 1.5,
        "is_special_item": 0,

        "prev_day_sales": 100,
        "prev_same_slot_sales": 110,
        "prev_week_same_day_slot_sales": 105,
        "avg_last_3_days_sales": 102,
        "avg_last_7_days_sales": 108,

        "sales_trend_3_days": 2,
        "sales_trend_weekly": 4,

        "demand_variance": 10,

        "quantity_prepared": 150,
        "quantity_wasted": 10,
        "leftover_percentage": 6,

        "max_capacity": 300,
        "staff_count": 6,

        "weather_type": weather,
        "temperature": input_data.get("temperature", 30)

    }

    # ---------------------------------------
    # CREATE DATAFRAME
    # ---------------------------------------

    df = pd.DataFrame([row])

    # ---------------------------------------
    # PREDICT
    # ---------------------------------------

    # If the trained model is not available, fall back to a simple heuristic
    if model is None:
        predicted_demand = int(df["quantity_prepared"].iloc[0] * 0.75) if "quantity_prepared" in df.columns else 100
    else:
        predicted_demand = int(model.predict(df)[0])

    suggested_preparation = int(predicted_demand * 1.1)

    # for now simulate actual sales
    actual_sold = predicted_demand - 5

    denominator = max(predicted_demand, actual_sold, 1)
    accuracy_percentage = round(
        (1 - abs(predicted_demand - actual_sold) / denominator) * 100,
        2,
    )

    log_prediction(
        food_item=input_data["food_item"],
        predicted_demand=predicted_demand,
        suggested_preparation=suggested_preparation,
        actual_sold=actual_sold
    )

    expected_waste = suggested_preparation - predicted_demand

    return {
        "predicted_demand": predicted_demand,
        "suggested_preparation": suggested_preparation,
        "actual_sold": actual_sold,
        "accuracy_percentage": accuracy_percentage,
        "expected_waste": expected_waste
    }



# ==========================================
# MENU OPTIMIZATION FUNCTION
# ==========================================

def menu_optimization():

    try:
        df = pd.read_csv("models/food_demand_dataset.csv")
    except FileNotFoundError:
        # Dataset missing; return empty values so backend stays up
        return {
            "high_demand_items": {},
            "low_demand_items": {},
            "optimization_suggestions": []
        }

    demand = df.groupby("food_item")["quantity_sold"].mean()

    demand = demand.sort_values(ascending=False)

    high_demand = demand.head(3)
    low_demand = demand.tail(3)

    # Generate optimization suggestions
    suggestions = []

    # High demand suggestions
    for item, avg_sales in high_demand.items():
        current_prep = df[df["food_item"] == item]["quantity_prepared"].mean()
        suggested_prep = int(current_prep * 1.2)  # Increase by 20%
        suggestions.append({
            "food_item": item,
            "current_average_sales": int(avg_sales),
            "current_average_preparation": int(current_prep),
            "suggested_preparation": suggested_prep,
            "action": "Increase preparation by 20%",
            "reason": "High demand detected - prevent stockouts"
        })

    # Low demand suggestions
    for item, avg_sales in low_demand.items():
        current_prep = df[df["food_item"] == item]["quantity_prepared"].mean()
        suggested_prep = int(current_prep * 0.85)  # Reduce by 15%
        suggestions.append({
            "food_item": item,
            "current_average_sales": int(avg_sales),
            "current_average_preparation": int(current_prep),
            "suggested_preparation": suggested_prep,
            "action": "Reduce preparation by 15%",
            "reason": "Low demand detected - minimize waste"
        })

    return {
        "high_demand_items": high_demand.to_dict(),
        "low_demand_items": low_demand.to_dict(),
        "optimization_suggestions": suggestions
    }


# ==========================================
# REWARDS FUNCTION
# ==========================================

def get_rewards(points: int):

    if points >= 500:
        return "Free meal"
    elif points >= 250:
        return "10% discount"
    elif points >= 100:
        return "5% discount"
    else:
        return "No reward"


# ==========================================
# TEST PREDICTION (optional)
# ==========================================

if __name__ == "__main__":

    sample = {
        "food_item": "Burger",
        "time_slot": "11:00-13:00",
        "weather_type": "Sunny",
        "price": 90
    }

    result = predict_demand(sample)

    print("Predicted Demand:", result)

    menu_result = menu_optimization()

    print("Menu Optimization:", menu_result)

    # Test rewards
    test_points = [50, 100, 250, 500, 600]
    for pts in test_points:
        reward = get_rewards(pts)
        print(f"Points: {pts} -> Reward: {reward}")