from flask import Flask, request, jsonify
import sqlite3

app = Flask(__name__)

# -----------------------------
# DATABASE CONNECTION
# -----------------------------
def get_db():
    conn = sqlite3.connect("database.db")
    conn.row_factory = sqlite3.Row
    return conn

# -----------------------------
# TEST ROUTE
# -----------------------------
@app.route("/")
def home():
    return "Smart Food Prediction Backend Running!"

# -----------------------------
# SUBMIT STUDENT RESPONSE
# -----------------------------
@app.route("/submit-response", methods=["POST"])
def submit_response():
    data = request.json
    
    user_id = data["user_id"]
    date = data["date"]
    is_coming = data["is_coming"]
    selected_dishes = data["selected_dishes"]

    conn = get_db()
    conn.execute(
        "INSERT INTO daily_responses (user_id, date, is_coming, selected_dishes) VALUES (?, ?, ?, ?)",
        (user_id, date, is_coming, selected_dishes)
    )
    conn.commit()
    conn.close()

    return jsonify({"message": "Response saved successfully"})

# -----------------------------
if __name__ == "__main__":
    app.run(debug=True)
