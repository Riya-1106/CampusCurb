from flask import Flask, request, jsonify
import sqlite3
from datetime import datetime
import pandas as pd
import joblib

model = joblib.load("model/food_model.pkl")
app = Flask(__name__)

# -------------------------
# DATABASE CONNECTION
# -------------------------
def get_db():
    conn = sqlite3.connect("database.db")
    conn.row_factory = sqlite3.Row
    return conn

# -------------------------
# HOME ROUTE
# -------------------------
@app.route("/")
def home():
    return "Smart Food Prediction Backend Running!"

# -------------------------
# ADD USER
# -------------------------
@app.route("/add-user", methods=["POST"])
def add_user():
    data = request.json
    conn = get_db()

    conn.execute("""
        INSERT INTO users (name, department, year, is_hosteller)
        VALUES (?, ?, ?, ?)
    """, (data["name"], data["department"], data["year"], data["is_hosteller"]))

    conn.commit()
    conn.close()

    return jsonify({"message": "User Added Successfully"})

# -------------------------
# SUBMIT RESPONSE
# -------------------------
@app.route("/submit-response", methods=["POST"])
def submit_response():
    data = request.json
    conn = get_db()

    conn.execute("""
        INSERT INTO daily_responses 
        (user_id, date, time_slot, is_coming, selected_dish, notification_clicked, response_time)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """, (
        data["user_id"],
        data["date"],
        data["time_slot"],
        data["is_coming"],
        data["selected_dish"],
        data["notification_clicked"],
        datetime.now().strftime("%H:%M:%S")
    ))

    conn.commit()
    conn.close()

    return jsonify({"message": "Response Saved Successfully"})

# -------------------------
# GET DAILY CONFIRMED COUNT
# -------------------------
@app.route("/get-confirmed-count", methods=["POST"])
def get_confirmed():
    data = request.json
    conn = get_db()

    cursor = conn.execute("""
        SELECT COUNT(*) as total 
        FROM daily_responses
        WHERE date = ? AND time_slot = ? AND is_coming = 1
    """, (data["date"], data["time_slot"]))

    result = cursor.fetchone()
    conn.close()

    return jsonify({"confirmed_count": result["total"]})

# -------------------------
# PREDICT FOOD QUANTITY
# -------------------------
@app.route("/predict", methods=["POST"])
def predict_food():

    data = request.json
    date = data["date"]
    time_slot = data["time_slot"]
    food_item = data["food_item"]

    conn = get_db()

    # 1️⃣ Get confirmed attendance
    cursor = conn.execute("""
        SELECT COUNT(*) as total
        FROM daily_responses
        WHERE date = ? AND time_slot = ? AND is_coming = 1
    """, (date, time_slot))

    confirmed_count = cursor.fetchone()["total"]

    # 2️⃣ Get dish click count
    cursor = conn.execute("""
        SELECT SUM(click_count) as clicks
        FROM dish_clicks
        WHERE date = ? AND time_slot = ? AND food_item = ?
    """, (date, time_slot, food_item))

    result = cursor.fetchone()
    dish_click_count = result["clicks"] if result["clicks"] else 0

    conn.close()

    # 3️⃣ Prepare ML input
    input_data = pd.DataFrame([{
        "confirmed_attendance_count": confirmed_count,
        "dish_click_count": dish_click_count,
        "is_weekend": 0,
        "is_holiday": 0,
        "temperature": 30
    }])

    # ⚠ IMPORTANT:
    # Columns must match training columns exactly
    input_data = pd.get_dummies(input_data)
    input_data = input_data.reindex(columns=model.feature_names_in_, fill_value=0)

    # 4️⃣ Predict
    prediction = model.predict(input_data)[0]

    # 5️⃣ Add 10% buffer
    final_quantity = int(prediction * 1.10)

    # 6️⃣ Store in prediction_log
    conn = get_db()
    conn.execute("""
        INSERT INTO prediction_log 
        (date, time_slot, food_item, confirmed_count, predicted_quantity, buffer_added)
        VALUES (?, ?, ?, ?, ?, ?)
    """, (date, time_slot, food_item, confirmed_count, final_quantity, int(prediction*0.10)))

    conn.commit()
    conn.close()

    return jsonify({
        "food_item": food_item,
        "predicted_quantity": final_quantity
    })

# -------------------------
if __name__ == "__main__":
    app.run(debug=True)
