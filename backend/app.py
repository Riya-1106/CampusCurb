from fastapi import FastAPI
from pydantic import BaseModel
import pandas as pd
import subprocess

from predict import predict_demand, get_rewards
from waste_analytics import waste_analysis

app = FastAPI()

# ==========================================
# INPUT MODEL FOR PREDICTION
# ==========================================

class PredictionInput(BaseModel):

    food_item: str
    time_slot: str
    weather_type: str
    price: int
    temperature: int


# ==========================================
# HOME ROUTE
# ==========================================

@app.get("/")
def home():
    return {"message": "Food Demand Prediction API Running"}


# ==========================================
# PREDICT DEMAND
# ==========================================

@app.post("/predict")
def predict(data: PredictionInput):

    input_data = {

        "food_item": data.food_item,
        "time_slot": data.time_slot,
        "weather_type": data.weather_type,
        "price": data.price,
        "temperature": data.temperature

    }

    prediction = predict_demand(input_data)

    return {
        "predicted_demand": prediction["predicted_demand"],
        "suggested_preparation": prediction["suggested_preparation"]
    }


# ==========================================
# MENU OPTIMIZATION
# ==========================================

@app.get("/menu-optimization")
def menu_analysis():

    from predict import menu_optimization

    return menu_optimization()

# ==========================================
# STUDENT ANALYTICS
# ==========================================

@app.get("/student-analytics")
def analytics():

    from student_analytics import student_behavior

    return student_behavior()

# ==========================================
# GET REWARDS
# ==========================================

@app.get("/rewards/{points}")
def get_user_rewards(points: int):

    reward = get_rewards(points)

    return {"points": points, "reward": reward}


# ==========================================
# GET DAILY FORECAST
# ==========================================

@app.get("/forecast")
def forecast():

    df = pd.read_csv("data/tomorrow_forecast.csv")

    return df.to_dict(orient="records")

@app.get("/waste-analytics")
def waste():

    return waste_analysis()


@app.get("/waste-report")
def waste_report():

    report = waste_analysis()
    if "error" in report:
        return report

    return {
        "Total Prepared": report.get("total_food_prepared", 0),
        "Total Sold": report.get("total_food_sold", 0),
        "Total Wasted": report.get("total_food_wasted", 0),
        "Waste Percentage": f"{int(round(report.get('waste_percentage', 0)))}%",
        "Estimated ML Waste Reduction": int(round(report.get("estimated_reduction", 0)))
    }


# ==========================================
# WASTE ANALYTICS (Flutter compatible)
# ==========================================

@app.get("/waste_analytics")
def waste_analytics():

    return waste_analysis()


# ==========================================
# DEMAND FORECAST DASHBOARD
# ==========================================

@app.get("/demand-dashboard")
def demand_dashboard():
    # Fixed set of canteen menu items for dashboard
    items = ["Burger", "Pizza", "Sandwich"]

    base_input = {
        "time_slot": "11:00-13:00",
        "weather_type": "Sunny",
        "price": 90,
        "temperature": 25
    }

    rows = []
    for item in items:
        input_data = {**base_input, "food_item": item}
        pred = predict_demand(input_data)
        rows.append({
            "food_item": item,
            "predicted_demand": pred["predicted_demand"],
            "suggested_preparation": pred["suggested_preparation"]
        })

    return {
        "dashboard": rows,
        "formula": "predicted_demand + safety_margin (10%)",
        "example": "120 + 10% = 132"
    }


# ==========================================
# RETRAIN MODEL
# ==========================================

@app.post("/retrain")
def retrain():

    subprocess.run(["python", "firebase_to_dataset.py"])
    subprocess.run(["python", "train.py"])

    return {"message": "Model retrained successfully"}