from flask import Flask, request, jsonify
import pickle
import pandas as pd
import os

app = Flask(__name__)

# Load model
model_path = os.path.join("model", "food_model.pkl")
encoder_path = os.path.join("model", "label_encoder.pkl")

model = pickle.load(open(model_path, "rb"))
label_encoder = pickle.load(open(encoder_path, "rb"))

@app.route("/")
def home():
    return "Smart Canteen ML API Running 🚀"

@app.route("/predict", methods=["POST"])
def predict():

    data = request.json

    try:
        food_item = label_encoder.transform([data["food_item"]])[0]

        input_data = pd.DataFrame([{
            "day_of_week": data["day_of_week"],
            "week_of_year": data["week_of_year"],
            "food_item": food_item,
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
