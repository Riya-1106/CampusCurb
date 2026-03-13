import firebase_admin
from firebase_admin import credentials, firestore
import pandas as pd
from datetime import datetime
import random

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

    date_obj = datetime.strptime(order["date"], "%Y-%m-%d")

    quantity_sold = order["quantity"]

    quantity_prepared = quantity_sold + random.randint(5,25)

    row = {

        "date": order["date"],

        "day_of_week": date_obj.weekday(),

        "week_of_year": date_obj.isocalendar()[1],

        "month": date_obj.month,

        "time_slot": order["time_slot"],

        "is_weekend": 1 if date_obj.weekday() >= 5 else 0,

        "is_holiday": 0,

        "is_exam_day": random.choice([0,1]),

        "food_item": order["food_item"],

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

        "quantity_wasted": quantity_prepared - quantity_sold,

        "leftover_percentage": ((quantity_prepared - quantity_sold)/quantity_prepared)*100,

        "max_capacity": 300,

        "staff_count": random.randint(4,8),

        "weather_type": random.choice(["Sunny","Rainy","Cloudy"]),

        "temperature": random.randint(24,36)

    }

    data.append(row)

df = pd.DataFrame(data)

df.to_csv("data/weekly_data.csv", index=False)

print("Weekly dataset created")
print(df.head())