import pandas as pd
import numpy as np
import random
from datetime import datetime, timedelta
import os

# Ensure data folder exists
os.makedirs("../data", exist_ok=True)

np.random.seed(42)

rows = 5000

food_items = [
    "Veg Biryani", "Chicken Biryani", "Fried Rice", "Schezwan Fried Rice,"
    "Paneer Butter Masala", "Chole Bhature",
    "Masala Dosa", "Idli Sambar", "Pasta",
    "Fries", "Sandwich", "Noodles",
    "Paratha", "Rajma Rice", "Dal Tadka",
    "Upma", "Poha"
]

data = []
start_date = datetime(2024, 1, 1)

for i in range(rows):
    date = start_date + timedelta(days=i % 365)
    day_of_week = date.weekday()
    week_of_year = date.isocalendar()[1]

    food = random.choice(food_items)

    temperature = np.random.normal(30, 5)
    is_exam_day = random.choice([0, 1])
    is_event_day = random.choice([0, 1])
    is_holiday = 1 if day_of_week == 6 else 0

    avg_last_7_days_sales = np.random.randint(60, 150)
    prev_day_sales = avg_last_7_days_sales + np.random.randint(-15, 15)

    # Demand logic
    demand = avg_last_7_days_sales

    if is_event_day:
        demand += 20

    if is_exam_day:
        demand -= 25

    if is_holiday:
        demand -= 30

    demand += np.random.randint(-10, 10)

    buffer = np.random.randint(5, 20)
    quantity_prepared = max(demand + buffer, 0)

    actual_sales = max(demand + np.random.randint(-15, 15), 0)

    leftover_quantity = max(quantity_prepared - actual_sales, 0)

    data.append([
        date,
        day_of_week,
        week_of_year,
        food,
        round(temperature, 2),
        is_exam_day,
        is_event_day,
        is_holiday,
        avg_last_7_days_sales,
        prev_day_sales,
        quantity_prepared,
        actual_sales,
        leftover_quantity
    ])

columns = [
    "date",
    "day_of_week",
    "week_of_year",
    "food_item",
    "temperature",
    "is_exam_day",
    "is_event_day",
    "is_holiday",
    "avg_last_7_days_sales",
    "prev_day_sales",
    "quantity_prepared",
    "actual_sales",
    "leftover_quantity"
]

df = pd.DataFrame(data, columns=columns)

df.to_csv("../data/generated_dataset.csv", index=False)

print("✅ Dataset generated successfully!")
print("Rows:", len(df))
