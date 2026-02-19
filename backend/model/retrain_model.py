import sqlite3
import pandas as pd
import pickle
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.preprocessing import LabelEncoder
import os

DATABASE = "../database.db"

# Connect DB
conn = sqlite3.connect(DATABASE)

# Pull real data
query = """
SELECT 
    a.food_item_id,
    a.quantity_sold,
    a.date,
    w.temperature,
    e.is_exam_day,
    e.is_event_day,
    e.is_holiday
FROM actual_sales a
LEFT JOIN weather_data w 
ON a.date = w.date
LEFT JOIN event_calendar e 
ON a.date = e.date
"""

df = pd.read_sql_query(query, conn)
conn.close()

if len(df) < 20:
    print("Not enough data to retrain yet.")
    exit()

# Feature Engineering
df["date"] = pd.to_datetime(df["date"])
df["day_of_week"] = df["date"].dt.weekday
df["week_of_year"] = df["date"].dt.isocalendar().week

df = df.fillna(0)

# Encode food
le = LabelEncoder()
df["food_item"] = le.fit_transform(df["food_item_id"])

X = df[[
    "day_of_week",
    "week_of_year",
    "food_item",
    "temperature",
    "is_exam_day",
    "is_event_day",
    "is_holiday"
]]

y = df["quantity_sold"]

# Train
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2)

model = RandomForestRegressor(n_estimators=200)
model.fit(X_train, y_train)

pred = model.predict(X_test)

mae = mean_absolute_error(y_test, pred)
rmse = mean_squared_error(y_test, pred) ** 0.5
r2 = r2_score(y_test, pred)

print("Retrained Model Performance")
print("MAE:", round(mae, 2))
print("RMSE:", round(rmse, 2))
print("R2:", round(r2, 3))

# Save updated model
pickle.dump(model, open("food_model.pkl", "wb"))
pickle.dump(le, open("label_encoder.pkl", "wb"))

print("Model retrained and updated successfully!")
