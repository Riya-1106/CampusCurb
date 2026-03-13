import pandas as pd
import joblib
from datetime import datetime, timedelta
import random

# ======================================
# LOAD MODEL
# ======================================

model = joblib.load("models/best_model.pkl")

dataset = pd.read_csv("models/food_demand_dataset.csv")

# ======================================
# GET FOOD ITEMS
# ======================================

food_items = dataset["food_item"].unique()

# ======================================
# CREATE TOMORROW DATE
# ======================================

tomorrow = datetime.now() + timedelta(days=1)

forecast_data = []

for food in food_items:

    row = {

        "day_of_week": tomorrow.weekday(),
        "week_of_year": tomorrow.isocalendar()[1],
        "month": tomorrow.month,
        "time_slot": random.choice(["09:00-11:00","11:00-13:00","13:00-15:00"]),
        "is_weekend": 1 if tomorrow.weekday()>=5 else 0,
        "is_holiday": 0,
        "is_exam_day": 0,
        "food_item": food,
        "food_category": "FastFood",
        "is_veg": random.choice([0,1]),
        "price": random.randint(30,120),
        "portion_size": 1.5,
        "is_special_item": 0,
        "prev_day_sales": random.randint(80,150),
        "prev_same_slot_sales": random.randint(80,150),
        "prev_week_same_day_slot_sales": random.randint(80,150),
        "avg_last_3_days_sales": random.randint(80,150),
        "avg_last_7_days_sales": random.randint(80,150),
        "sales_trend_3_days": random.randint(-10,10),
        "sales_trend_weekly": random.randint(-20,20),
        "demand_variance": random.randint(5,15),
        "quantity_prepared": random.randint(120,200),
        "quantity_wasted": random.randint(5,20),
        "leftover_percentage": random.uniform(5,20),
        "max_capacity": 300,
        "staff_count": 6,
        "weather_type": random.choice(["Sunny","Rainy","Cloudy"]),
        "temperature": random.randint(24,36)

    }

    df = pd.DataFrame([row])

    prediction = model.predict(df)[0]

    forecast_data.append({

        "food_item": food,
        "predicted_demand": int(prediction)

    })

forecast_df = pd.DataFrame(forecast_data)

forecast_df.to_csv("data/tomorrow_forecast.csv", index=False)

print("Tomorrow demand forecast generated")
print(forecast_df)