import pandas as pd
import numpy as np
import joblib
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import r2_score

# -----------------------------
# 1️⃣ Generate Synthetic Training Data
# -----------------------------
np.random.seed(42)

rows = 2000

data = pd.DataFrame({
    "confirmed_attendance_count": np.random.randint(50, 300, rows),
    "dish_click_count": np.random.randint(20, 250, rows),
    "is_weekend": np.random.randint(0, 2, rows),
    "is_holiday": np.random.randint(0, 2, rows),
    "temperature": np.random.randint(22, 38, rows)
})

# -----------------------------
# 2️⃣ Create Target Variable
# Logic: preparation depends on attendance + clicks + weather
# -----------------------------
data["quantity_prepared"] = (
    data["confirmed_attendance_count"] * 0.6 +
    data["dish_click_count"] * 0.4 +
    data["temperature"] * 1.5 +
    np.random.normal(0, 10, rows)
).astype(int)

# -----------------------------
# 3️⃣ Split Data
# -----------------------------
X = data.drop("quantity_prepared", axis=1)
y = data["quantity_prepared"]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

# -----------------------------
# 4️⃣ Train Random Forest
# -----------------------------
model = RandomForestRegressor(
    n_estimators=200,
    random_state=42
)

model.fit(X_train, y_train)

# -----------------------------
# 5️⃣ Evaluate
# -----------------------------
predictions = model.predict(X_test)
r2 = r2_score(y_test, predictions)

print("Model R2 Score:", round(r2, 3))

# -----------------------------
# 6️⃣ Save Model
# -----------------------------
joblib.dump(model, "../backend/model/food_model.pkl")

print("✅ Model saved as food_model.pkl")
