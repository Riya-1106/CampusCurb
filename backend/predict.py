import joblib
import pandas as pd

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
        prediction = int(df["quantity_prepared"].iloc[0] * 0.75) if "quantity_prepared" in df.columns else 100
    else:
        prediction = int(model.predict(df)[0])

    # safety margin (10%)
    suggested_preparation = int(prediction * 1.1)

    expected_waste = suggested_preparation - prediction

    return {
        "predicted_demand": prediction,
        "suggested_preparation": suggested_preparation,
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
            "low_demand_items": {}
        }

    demand = df.groupby("food_item")["quantity_sold"].mean()

    demand = demand.sort_values(ascending=False)

    high_demand = demand.head(3)
    low_demand = demand.tail(3)

    return {
        "high_demand_items": high_demand.to_dict(),
        "low_demand_items": low_demand.to_dict()
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