from flask import Flask, request, jsonify
from flask_cors import CORS
import sqlite3
import pickle
import pandas as pd
import os
from apscheduler.schedulers.background import BackgroundScheduler
import subprocess

app = Flask(__name__)
CORS(app)

DATABASE = "database.db"

# Load ML model
model = pickle.load(open(os.path.join("model", "food_model.pkl"), "rb"))
label_encoder = pickle.load(open(os.path.join("model", "label_encoder.pkl"), "rb"))


# -----------------------
# Database Connection
# -----------------------
def get_db_connection():
    conn = sqlite3.connect(DATABASE)
    conn.row_factory = sqlite3.Row
    return conn


# -----------------------
# Home Route
# -----------------------
@app.route("/")
def home():
    return "Smart Canteen Backend Running 🚀"


# -----------------------
# Register User
# -----------------------
@app.route("/register", methods=["POST"])
def register():

    data = request.json
    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("""
        INSERT INTO users (name, email, password, role, campus_id)
        VALUES (?, ?, ?, ?, ?)
    """, (
        data["name"],
        data["email"],
        data["password"],
        data["role"],
        data["campus_id"]
    ))

    conn.commit()
    conn.close()

    return jsonify({"message": "User registered successfully"})


# -----------------------
# Login User
# -----------------------
@app.route("/login", methods=["POST"])
def login():

    data = request.json
    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT * FROM users WHERE email=? AND password=?
    """, (data["email"], data["password"]))

    user = cursor.fetchone()
    conn.close()

    if user:
        return jsonify({
            "message": "Login successful",
            "user_id": user["id"],
            "role": user["role"]
        })
    else:
        return jsonify({"error": "Invalid credentials"}), 401


# -----------------------
# Add Food Item (Canteen)
# -----------------------
@app.route("/add-food", methods=["POST"])
def add_food():

    data = request.json
    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("""
        INSERT INTO food_items (food_name, category, price)
        VALUES (?, ?, ?)
    """, (
        data["food_name"],
        data["category"],
        data["price"]
    ))

    conn.commit()
    conn.close()

    return jsonify({"message": "Food item added"})


# -----------------------
# Prediction API
# -----------------------
@app.route("/predict", methods=["POST"])
def predict():

    data = request.json

    try:
        food_item_encoded = label_encoder.transform([data["food_item"]])[0]

        input_data = pd.DataFrame([{
            "day_of_week": data["day_of_week"],
            "week_of_year": data["week_of_year"],
            "food_item": food_item_encoded,
            "temperature": data["temperature"],
            "is_exam_day": data["is_exam_day"],
            "is_event_day": data["is_event_day"],
            "is_holiday": data["is_holiday"],
            "avg_last_7_days_sales": data["avg_last_7_days_sales"],
            "prev_day_sales": data["prev_day_sales"]
        }])

        prediction = model.predict(input_data)[0]

        return jsonify({
            "predicted_servings": round(float(prediction), 2)
        })

    except Exception as e:
        return jsonify({"error": str(e)})

# -----------------------
# Get Daily Menu
# -----------------------
@app.route("/get-menu", methods=["GET"])
def get_menu():

    campus_id = request.args.get("campus_id")
    date = request.args.get("date")

    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT daily_menu.id, food_items.food_name, daily_menu.timing_slot
        FROM daily_menu
        JOIN food_items ON daily_menu.food_item_id = food_items.id
        WHERE daily_menu.campus_id=? AND daily_menu.date=?
    """, (campus_id, date))

    menu = cursor.fetchall()
    conn.close()

    return jsonify([dict(row) for row in menu])

# -----------------------
# Submit Student Response
# -----------------------
@app.route("/submit-response", methods=["POST"])
def submit_response():

    data = request.json

    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("""
        INSERT INTO student_responses 
        (user_id, food_item_id, date, will_attend, clicked_food, submitted_response)
        VALUES (?, ?, ?, ?, ?, ?)
    """, (
        data["user_id"],
        data["food_item_id"],
        data["date"],
        data["will_attend"],
        data["clicked_food"],
        data["submitted_response"]
    ))

    # Add reward points
    cursor.execute("""
        UPDATE rewards
        SET points = points + 5
        WHERE user_id=?
    """, (data["user_id"],))

    conn.commit()
    conn.close()

    return jsonify({"message": "Response recorded successfully"})

# -----------------------
# Expected Demand
# -----------------------
@app.route("/expected-demand", methods=["GET"])
def expected_demand():

    food_item_id = request.args.get("food_item_id")
    date = request.args.get("date")

    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT COUNT(*) as total_attending
        FROM student_responses
        WHERE food_item_id=? AND date=? AND will_attend=1
    """, (food_item_id, date))

    attending = cursor.fetchone()["total_attending"]

    cursor.execute("""
        SELECT COUNT(*) as total_clicks
        FROM student_responses
        WHERE food_item_id=? AND date=? AND clicked_food=1
    """, (food_item_id, date))

    clicks = cursor.fetchone()["total_clicks"]

    conn.close()

    return jsonify({
        "expected_attendance": attending,
        "food_interest_clicks": clicks
    })
# -----------------------
# Smart Prediction Engine
# -----------------------
@app.route("/smart-predict", methods=["POST"])
def smart_predict():

    data = request.json
    campus_id = data["campus_id"]
    food_item_id = data["food_item_id"]
    date = data["date"]

    conn = get_db_connection()
    cursor = conn.cursor()

    # 1️⃣ Get student attendance count
    cursor.execute("""
        SELECT COUNT(*) as total_attending
        FROM student_responses
        WHERE food_item_id=? AND date=? AND will_attend=1
    """, (food_item_id, date))
    attendance = cursor.fetchone()["total_attending"]

    # 2️⃣ Get previous day sales
    cursor.execute("""
        SELECT quantity_sold
        FROM actual_sales
        WHERE food_item_id=? AND date < ?
        ORDER BY date DESC
        LIMIT 1
    """, (food_item_id, date))
    prev = cursor.fetchone()
    prev_day_sales = prev["quantity_sold"] if prev else 80

    # 3️⃣ Get weather
    cursor.execute("""
        SELECT temperature
        FROM weather_data
        WHERE campus_id=? AND date=?
    """, (campus_id, date))
    weather = cursor.fetchone()
    temperature = weather["temperature"] if weather else 30

    # 4️⃣ Get event data
    cursor.execute("""
        SELECT is_exam_day, is_event_day, is_holiday
        FROM event_calendar
        WHERE campus_id=? AND date=?
    """, (campus_id, date))
    event = cursor.fetchone()

    if event:
        is_exam_day = event["is_exam_day"]
        is_event_day = event["is_event_day"]
        is_holiday = event["is_holiday"]
    else:
        is_exam_day = 0
        is_event_day = 0
        is_holiday = 0

    conn.close()

    # Encode food item
    food_name = data["food_name"]
    food_encoded = label_encoder.transform([food_name])[0]

    # Build model input
    input_data = pd.DataFrame([{
        "day_of_week": pd.to_datetime(date).weekday(),
        "week_of_year": pd.to_datetime(date).week,
        "food_item": food_encoded,
        "temperature": temperature,
        "is_exam_day": is_exam_day,
        "is_event_day": is_event_day,
        "is_holiday": is_holiday,
        "avg_last_7_days_sales": attendance,
        "prev_day_sales": prev_day_sales
    }])

    prediction = model.predict(input_data)[0]

    # 🧠 Adaptive buffer per food item
    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT 
            AVG(ABS(final_prediction - actual_sold) * 1.0 / final_prediction) as error_percent
        FROM predictions
        WHERE food_item_id=? 
        AND actual_sold IS NOT NULL
    """, (food_item_id,))

    result = cursor.fetchone()
    conn.close()

    if result["error_percent"]:
        adaptive_buffer_percent = result["error_percent"]
    else:
        adaptive_buffer_percent = 0.10  # default 10%

    buffer = int(prediction * adaptive_buffer_percent)
    final_prediction = int(prediction + buffer)


    # 🔥 STORE PREDICTION
    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("""
        INSERT INTO predictions
        (campus_id, food_item_id, date, base_prediction, buffer_added, final_prediction)
        VALUES (?, ?, ?, ?, ?, ?)
    """, (
        campus_id,
        food_item_id,
        date,
        float(prediction),
        buffer,
        final_prediction
    ))

    conn.commit()
    conn.close()

    return jsonify({
        "base_prediction": round(float(prediction), 2),
        "buffer_added": buffer,
        "final_servings_to_prepare": final_prediction
    })

@app.route("/update-actual-sales", methods=["POST"])
def update_actual_sales():

    data = request.json
    campus_id = data["campus_id"]
    food_item_id = data["food_item_id"]
    date = data["date"]
    actual_sold = data["actual_sold"]

    conn = get_db_connection()
    cursor = conn.cursor()

    # Update prediction record
    cursor.execute("""
        SELECT final_prediction FROM predictions
        WHERE campus_id=? AND food_item_id=? AND date=?
    """, (campus_id, food_item_id, date))

    record = cursor.fetchone()
    # Bonus reward for attendance
    cursor.execute("""
        UPDATE rewards
        SET points = points + 10
        WHERE user_id IN (
            SELECT user_id FROM student_responses
            WHERE date=? AND will_attend=1
        )
    """, (date,))

    if record:
        predicted = record["final_prediction"]
        error = abs(predicted - actual_sold)

        cursor.execute("""
            UPDATE predictions
            SET actual_sold=?, error_value=?
            WHERE campus_id=? AND food_item_id=? AND date=?
        """, (actual_sold, error,
              campus_id, food_item_id, date))

    conn.commit()
    conn.close()

    return jsonify({"message": "Actual sales updated"})

@app.route("/get-rewards", methods=["GET"])
def get_rewards():
    user_id = request.args.get("user_id")

    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT points FROM rewards WHERE user_id=?
    """, (user_id,))

    result = cursor.fetchone()
    conn.close()

    points = result["points"] if result else 0

    return jsonify({"reward_points": points})

@app.route("/leaderboard", methods=["GET"])
def leaderboard():

    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT users.name, rewards.points
        FROM rewards
        JOIN users ON rewards.user_id = users.id
        ORDER BY rewards.points DESC
        LIMIT 10
    """)

    leaders = cursor.fetchall()
    conn.close()

    return jsonify([dict(row) for row in leaders])

@app.route("/waste-score", methods=["GET"])
def waste_score():

    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT 
            SUM(final_prediction) as total_prepared,
            SUM(final_prediction - actual_sold) as total_waste
        FROM predictions
        WHERE actual_sold IS NOT NULL
    """)

    result = cursor.fetchone()
    conn.close()

    if result["total_prepared"] and result["total_waste"] is not None:
        waste_percent = (result["total_waste"] / result["total_prepared"]) * 100
    else:
        waste_percent = 0

    return jsonify({
        "waste_percentage": round(waste_percent, 2)
    })

@app.route("/food-waste-score", methods=["GET"])
def food_waste_score():

    food_item_id = request.args.get("food_item_id")

    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT 
            SUM(final_prediction) as total_prepared,
            SUM(final_prediction - actual_sold) as total_waste
        FROM predictions
        WHERE food_item_id=? 
        AND actual_sold IS NOT NULL
    """, (food_item_id,))

    result = cursor.fetchone()
    conn.close()

    if result["total_prepared"] and result["total_waste"] is not None:
        waste_percent = (result["total_waste"] / result["total_prepared"]) * 100
    else:
        waste_percent = 0

    return jsonify({
        "food_waste_percentage": round(waste_percent, 2)
    })

def weekly_retrain():
    subprocess.call(["python", "model/retrain_model.py"])

scheduler = BackgroundScheduler()
scheduler.add_job(weekly_retrain, 'interval', weeks=1)
scheduler.start()

if __name__ == "__main__":
    app.run(debug=True)
