from flask import Flask, request, jsonify
from flask_cors import CORS
import sqlite3
import pickle
import pandas as pd
import os

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


if __name__ == "__main__":
    app.run(debug=True)
