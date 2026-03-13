import pandas as pd
import numpy as np
import random
from datetime import datetime, timedelta

rows = 5204   # dataset size

food_items = ["Burger","Sandwich","Pizza","Tea","Coffee","Milk","Pasta","Noodles"]
categories = {
    "Burger":"FastFood",
    "Sandwich":"FastFood",
    "Pizza":"FastFood",
    "Tea":"Beverage",
    "Coffee":"Beverage",
    "Milk":"Beverage",
    "Pasta":"FastFood",
    "Noodles":"FastFood"
}

weather_types = ["Sunny","Cloudy","Rainy"]

start_date = datetime(2024,1,1)

data = []

for i in range(rows):

    date = start_date + timedelta(days=random.randint(0,120))
    food = random.choice(food_items)

    prev_day = random.randint(50,200)
    prev_slot = prev_day + random.randint(-20,20)

    quantity_prepared = random.randint(80,220)

    noise = random.randint(-10, 10)
    quantity_sold = quantity_prepared - random.randint(0,40) + noise    

    weather = random.choice(weather_types)

    if weather == "Rainy":
        quantity_prepared = random.randint(120,220)  # more tea/coffee demand
    elif weather == "Sunny":
        quantity_prepared = random.randint(80,180)
    else:
        quantity_prepared = random.randint(100,200)

    slot = random.choice(["09:00-11:00","11:00-13:00","13:00-15:00"])
    if slot == "11:00-13:00":
        quantity_prepared += random.randint(30,60)  # lunch peak

    row = {

        "date":date.strftime("%Y-%m-%d"),
        "day_of_week":date.weekday(),
        "week_of_year":date.isocalendar()[1],
        "month":date.month,

        "time_slot":random.choice(["09:00-11:00","11:00-13:00","13:00-15:00"]),

        "is_weekend":1 if date.weekday()>=5 else 0,
        "is_holiday":random.choice([0,0,0,1]),
        "is_exam_day":random.choice([0,0,1]),

        "food_item":food,
        "food_category":categories[food],

        "is_veg":random.choice([0,1]),

        "price":random.randint(20,120),

        "portion_size":random.choice([1.0,1.5,2.0]),

        "is_special_item":random.choice([0,0,1]),

        "prev_day_sales":prev_day,
        "prev_same_slot_sales":prev_slot,

        "prev_week_same_day_slot_sales":prev_day + random.randint(-30,30),

        "avg_last_3_days_sales":prev_day + random.randint(-15,15),
        "avg_last_7_days_sales":prev_day + random.randint(-25,25),

        "sales_trend_3_days":random.randint(-20,20),
        "sales_trend_weekly":random.randint(-30,30),

        "demand_variance":random.randint(1,25),

        "quantity_prepared":quantity_prepared,
        "quantity_sold":quantity_sold,

        "quantity_wasted":quantity_prepared - quantity_sold,

        "leftover_percentage":round(((quantity_prepared - quantity_sold)/quantity_prepared)*100,2),

        "max_capacity":random.randint(200,350),

        "staff_count":random.randint(3,10),

        "weather_type":random.choice(weather_types),

        "temperature":random.randint(22,38)

    }

    data.append(row)

df = pd.DataFrame(data)

# introduce missing values intentionally
for col in df.columns:
    df.loc[df.sample(frac=0.05).index,col] = np.nan

df.to_csv("models/food_demand_dataset.csv",index=False)

print("Dataset generated successfully")
print(df.head())