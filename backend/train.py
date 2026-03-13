# ============================================
# STEP 1 : IMPORT LIBRARIES
# ============================================

import pandas as pd
import numpy as np

from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.preprocessing import StandardScaler
from sklearn.impute import SimpleImputer

from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error, r2_score

import joblib

# ============================================
# STEP 2 : LOAD DATASET
# ============================================

data = pd.read_csv("models/food_demand_dataset.csv")

print("Dataset Shape:",data.shape)

# ============================================
# STEP 3 : HANDLE MISSING VALUES
# ============================================

imputer = SimpleImputer(strategy="mean")

numeric_cols = data.select_dtypes(include=['float64','int64']).columns

data[numeric_cols] = imputer.fit_transform(data[numeric_cols])

data.fillna("Unknown",inplace=True)

# ============================================
# STEP 4 : FEATURE ENCODING
# ============================================

encoder = LabelEncoder()

categorical_cols = ["time_slot","food_item","food_category","weather_type"]

for col in categorical_cols:
    data[col] = encoder.fit_transform(data[col])

# ============================================
# STEP 5 : FEATURE SELECTION
# ============================================

target = "quantity_sold"

X = data.drop(columns=["quantity_sold","date"])
y = data[target]

# ============================================
# STEP 6 : TRAIN TEST SPLIT
# ============================================

X_train,X_test,y_train,y_test = train_test_split(
    X,y,test_size=0.2,random_state=42
)

# ============================================
# STEP 7 : FEATURE SCALING
# ============================================

scaler = StandardScaler()

X_train = scaler.fit_transform(X_train)
X_test = scaler.transform(X_test)

# ============================================
# STEP 8 : MODEL TRAINING
# ============================================

model = RandomForestRegressor(
    n_estimators=120,
    max_depth=12,
    random_state=42
)

model.fit(X_train,y_train)

# ============================================
# STEP 9 : MODEL EVALUATION
# ============================================

predictions = model.predict(X_test)

mae = mean_absolute_error(y_test,predictions)
r2 = r2_score(y_test,predictions)

print("Model Performance")
print("MAE:",mae)
print("R2 Score:",r2)

# ============================================
# STEP 10 : SAVE MODEL
# ============================================

joblib.dump(model,"models/food_demand_model.pkl")

print("Model saved successfully")