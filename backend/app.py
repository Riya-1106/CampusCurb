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

        "food_item": data.food_item,
        "predicted_demand": prediction

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


# ==========================================
# RETRAIN MODEL
# ==========================================

@app.post("/retrain")
def retrain():

    subprocess.run(["python", "firebase_to_dataset.py"])
    subprocess.run(["python", "retrain_model.py"])

    return {"message": "Model retrained successfully"}