import pandas as pd
import pickle
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import os

# Load dataset
df = pd.read_csv("../data/generated_dataset.csv")

# Encode food_item
label_encoder = LabelEncoder()
df["food_item"] = label_encoder.fit_transform(df["food_item"])

# Features and Target
X = df.drop(columns=[
    "date",
    "actual_sales",
    "quantity_prepared",
    "leftover_quantity"
])
y = df["actual_sales"]

# Train Test Split
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

# Model
model = RandomForestRegressor(
    n_estimators=200,
    max_depth=12,
    random_state=42
)

model.fit(X_train, y_train)

# Predictions
predictions = model.predict(X_test)

# Evaluation
mae = mean_absolute_error(y_test, predictions)
rmse = mean_squared_error(y_test, predictions) ** 0.5
r2 = r2_score(y_test, predictions)

print("📊 Model Performance")
print("MAE:", round(mae, 2))
print("RMSE:", round(rmse, 2))
print("R2 Score:", round(r2, 3))

# Save model
pickle.dump(model, open("food_model.pkl", "wb"))
pickle.dump(label_encoder, open("label_encoder.pkl", "wb"))

print("✅ Model saved successfully!")
