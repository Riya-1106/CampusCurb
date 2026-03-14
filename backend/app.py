from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import pandas as pd
import subprocess
import json
from pathlib import Path
from typing import List, Dict

from predict import predict_demand, get_rewards
from waste_analytics import waste_analysis

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Admin credentials (backend-only)
ADMIN_EMAIL = "CampusCurb30@gmail.com"
ADMIN_PASSWORD = "Campuscurb@2026"

class AdminLoginInput(BaseModel):
    email: str
    password: str

class AdminLoginResponse(BaseModel):
    success: bool
    role: str
    message: str

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
# ADMIN LOGIN (backend-only credentials)
# ==========================================

@app.post('/admin-login', response_model=AdminLoginResponse)
def admin_login(payload: AdminLoginInput):
    if payload.email.strip().lower() == ADMIN_EMAIL.lower() and payload.password == ADMIN_PASSWORD:
        return {
            "success": True,
            "role": "admin",
            "message": "Admin login successful"
        }
    return {
        "success": False,
        "role": "",
        "message": "Invalid admin credentials"
    }


# ==========================================
# ADMIN WORKFLOW STORAGE + ENDPOINTS
# ==========================================

DATA_DIR = Path("./data")
DATA_DIR.mkdir(exist_ok=True)
MENU_FILE = DATA_DIR / "admin_menu_pending.json"
EXCHANGE_FILE = DATA_DIR / "admin_exchange_requests.json"

MENU_MASTER = DATA_DIR / "menu.json"
ORDERS_FILE = DATA_DIR / "orders.json"
ATTENDANCE_FILE = DATA_DIR / "attendance.json"

DEFAULT_MENU_PENDING = [
    {
        "id": "m1",
        "name": "Veg Wrap",
        "price": 80,
        "category": "sandwich",
        "requestedBy": "canteen123",
        "createdAt": "2026-03-14T08:00:00Z"
    },
    {
        "id": "m2",
        "name": "Masala Dosa",
        "price": 50,
        "category": "breakfast",
        "requestedBy": "canteen123",
        "createdAt": "2026-03-14T08:20:00Z"
    }
]

DEFAULT_EXCHANGE_REQUESTS = [
    {
        "id": "e1",
        "title": "Exchange Veg Biryani for Paneer Rice",
        "requestedBy": "student001",
        "status": "pending",
        "createdAt": "2026-03-14T09:00:00Z"
    },
    {
        "id": "e2",
        "title": "Exchange French Fries for Salad",
        "requestedBy": "student002",
        "status": "pending",
        "createdAt": "2026-03-14T09:10:00Z"
    }
]

DEFAULT_MENU = [
    {"id": "1", "name": "Veg Wrap", "price": 80},
    {"id": "2", "name": "Masala Dosa", "price": 50},
    {"id": "3", "name": "Cheese Pizza", "price": 120},
]

DEFAULT_ORDERS = []
DEFAULT_ATTENDANCE = []


def load_data(path: Path, default):
    if not path.exists():
        path.write_text(json.dumps(default, indent=2))
    try:
        return json.loads(path.read_text())
    except Exception:
        path.write_text(json.dumps(default, indent=2))
        return default


def save_data(path: Path, payload):
    path.write_text(json.dumps(payload, indent=2))


@app.get("/admin/menu-pending")
def admin_menu_pending():
    return load_data(MENU_FILE, DEFAULT_MENU_PENDING)


class MenuAction(BaseModel):
    id: str


@app.post("/admin/menu-approve")
def admin_menu_approve(payload: MenuAction):
    items = load_data(MENU_FILE, DEFAULT_MENU_PENDING)
    remaining = [i for i in items if i.get("id") != payload.id]
    if len(remaining) == len(items):
        raise HTTPException(status_code=404, detail="Menu item not found")
    save_data(MENU_FILE, remaining)
    return {"message": "Menu item approved", "id": payload.id}


@app.post("/admin/menu-reject")
def admin_menu_reject(payload: MenuAction):
    items = load_data(MENU_FILE, DEFAULT_MENU_PENDING)
    remaining = [i for i in items if i.get("id") != payload.id]
    if len(remaining) == len(items):
        raise HTTPException(status_code=404, detail="Menu item not found")
    save_data(MENU_FILE, remaining)
    return {"message": "Menu item rejected", "id": payload.id}


@app.get("/admin/exchange-requests")
def admin_exchange_requests():
    return load_data(EXCHANGE_FILE, DEFAULT_EXCHANGE_REQUESTS)


class ExchangeStatus(BaseModel):
    id: str
    status: str


@app.post("/admin/exchange-status")
def admin_exchange_status(payload: ExchangeStatus):
    valid = {"approved", "rejected", "pending"}
    if payload.status not in valid:
        raise HTTPException(status_code=400, detail="Invalid status")
    requests = load_data(EXCHANGE_FILE, DEFAULT_EXCHANGE_REQUESTS)
    updated = False
    for req in requests:
        if req.get("id") == payload.id:
            req["status"] = payload.status
            updated = True
    if not updated:
        raise HTTPException(status_code=404, detail="Exchange request not found")
    save_data(EXCHANGE_FILE, requests)
    return {"message": "Exchange status updated", "id": payload.id, "status": payload.status}


# ==========================================
# STUDENT & CANTEEN PUBLIC API
# ==========================================

@app.get("/menu")
def get_menu():
    return load_data(MENU_MASTER, DEFAULT_MENU)


class CreateMenuItem(BaseModel):
    name: str
    price: int


@app.post("/menu")
def create_menu_item(item: CreateMenuItem):
    menu = load_data(MENU_MASTER, DEFAULT_MENU)
    new_id = str(len(menu) + 1)
    menu.append({"id": new_id, "name": item.name, "price": item.price})
    save_data(MENU_MASTER, menu)
    return {"message": "Menu item added", "id": new_id}


class OrderRequest(BaseModel):
    uid: str
    item: str
    price: int
    quantity: int


@app.post("/order")
def place_order(order: OrderRequest):
    orders = load_data(ORDERS_FILE, DEFAULT_ORDERS)
    orders.append({
        "id": str(len(orders) + 1),
        "uid": order.uid,
        "item": order.item,
        "price": order.price,
        "quantity": order.quantity,
        "time": pd.Timestamp.now().isoformat(),
    })
    save_data(ORDERS_FILE, orders)
    return {"message": "Order placed"}


class AttendanceRequest(BaseModel):
    uid: str
    date: str
    time: str


@app.post("/attendance")
def mark_attendance(att: AttendanceRequest):
    attendance = load_data(ATTENDANCE_FILE, DEFAULT_ATTENDANCE)
    found = next((a for a in attendance if a.get("uid") == att.uid and a.get("date") == att.date), None)
    if found:
        raise HTTPException(status_code=400, detail="Attendance already marked")
    attendance.append({
        "id": str(len(attendance) + 1),
        "uid": att.uid,
        "date": att.date,
        "time": att.time,
    })
    save_data(ATTENDANCE_FILE, attendance)
    return {"message": "Attendance marked"}


# ==========================================
# RETRAIN MODEL
# ==========================================

@app.post("/retrain")
def retrain():

    subprocess.run(["python", "firebase_to_dataset.py"])
    subprocess.run(["python", "train.py"])

    return {"message": "Model retrained successfully"}