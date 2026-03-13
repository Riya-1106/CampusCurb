from fastapi import FastAPI
from pydantic import BaseModel
import pandas as pd
import subprocess

from predict import predict_demand

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
# GET DAILY FORECAST
# ==========================================

@app.get("/forecast")
def forecast():

    df = pd.read_csv("data/tomorrow_forecast.csv")

    return df.to_dict(orient="records")


# ==========================================
# RETRAIN MODEL
# ==========================================

@app.post("/retrain")
def retrain():

    subprocess.run(["python", "firebase_to_dataset.py"])
    subprocess.run(["python", "retrain_model.py"])

    return {"message": "Model retrained successfully"}