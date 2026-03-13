from firebase_connect import db
from datetime import datetime

def log_prediction(food_item, predicted_demand, suggested_preparation, actual_sold):

    prediction_error = abs(predicted_demand - actual_sold)

    log_data = {
        "food_item": food_item,
        "predicted_demand": int(predicted_demand),
        "suggested_preparation": int(suggested_preparation),
        "actual_sold": int(actual_sold),
        "prediction_error": int(prediction_error),
        "date": datetime.now().strftime("%Y-%m-%d")
    }

    db.collection("prediction_logs").add(log_data)

    print("Prediction logged successfully")