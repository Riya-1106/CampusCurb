import firebase_admin
from firebase_admin import credentials, firestore
import pandas as pd
from datetime import datetime
import random
import os

# ==========================================
# STEP 1 : CONNECT FIREBASE
# ==========================================

cred = credentials.Certificate("firebase_key.json")
firebase_admin.initialize_app(cred)

db = firestore.client()

print("Connected to Firebase")

# ==========================================
# STEP 2 : FETCH ORDERS
# ==========================================

orders_ref = db.collection("orders")
docs = orders_ref.stream()

data = []

for doc in docs:

    order = doc.to_dict()

    try:
        date_obj = datetime.strptime(order["date"], "%Y-%m-%d")
    except:
        continue

    quantity_sold = order.get("quantity", 1)

    # simulate preparation
    quantity_prepared = quantity_sold + random.randint(5, 25)

    quantity_wasted = quantity_prepared - quantity_sold

    # avoid division error
    if quantity_prepared == 0:
        leftover_percentage = 0
    else:
        leftover_percentage = (quantity_wasted / quantity_prepared) * 100

    row = {

        "date": order["date"],
        "day_of_week": date_obj.weekday(),
        "week_of_year": date_obj.isocalendar()[1],
        "month": date_obj.month,
        "time_slot": order.get("time_slot", "11:00-13:00"),
        "is_weekend": 1 if date_obj.weekday() >= 5 else 0,
        "is_holiday": 0,
        "is_exam_day": random.choice([0,1]),

        "food_item": order.get("food_item","Burger"),
        "food_category": "FastFood",
        "is_veg": random.choice([0,1]),

        "price": random.randint(30,120),
        "portion_size": random.choice([1.0,1.5]),
        "is_special_item": 0,

        "prev_day_sales": random.randint(50,150),
        "prev_same_slot_sales": random.randint(50,150),
        "prev_week_same_day_slot_sales": random.randint(50,150),

        "avg_last_3_days_sales": random.randint(50,150),
        "avg_last_7_days_sales": random.randint(50,150),

        "sales_trend_3_days": random.randint(-20,20),
        "sales_trend_weekly": random.randint(-30,30),

        "demand_variance": random.randint(1,20),

        "quantity_prepared": quantity_prepared,
        "quantity_sold": quantity_sold,
        "quantity_wasted": quantity_wasted,

        "leftover_percentage": leftover_percentage,

        "max_capacity": 300,
        "staff_count": random.randint(4,8),

        "weather_type": random.choice(["Sunny","Rainy","Cloudy"]),
        "temperature": random.randint(24,36)

    }

    data.append(row)

# ==========================================
# STEP 3 : MERGE WITH EXISTING DATASET
# ==========================================

df_new = pd.DataFrame(data)

# Load existing dataset if it exists
existing_file = "models/food_demand_dataset.csv"
if os.path.exists(existing_file):
    df_existing = pd.read_csv(existing_file)
    print(f"Loaded existing dataset with {len(df_existing)} rows")

    # Append new data
    df_combined = pd.concat([df_existing, df_new], ignore_index=True)

    # Remove duplicates based on date and food_item (simple deduplication)
    df_combined = df_combined.drop_duplicates(subset=["date", "food_item"], keep="last")

    print(f"Combined dataset has {len(df_combined)} rows (added {len(df_new)} new rows)")
else:
    df_combined = df_new
    print(f"Created new dataset with {len(df_combined)} rows")

# Save merged dataset
os.makedirs("models", exist_ok=True)
df_combined.to_csv(existing_file, index=False)

print("Dataset merged and saved")
print(df_combined.head())