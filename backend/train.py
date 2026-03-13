# =====================================================
# STEP 1 : IMPORT LIBRARIES
# =====================================================

import pandas as pd
import numpy as np

from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.impute import SimpleImputer

from sklearn.linear_model import LinearRegression
from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor

from sklearn.metrics import mean_absolute_error, r2_score

import joblib
import matplotlib.pyplot as plt

# =====================================================
# STEP 2 : LOAD DATASET
# =====================================================

print("\nLoading Dataset...")

data = pd.read_csv("models/food_demand_dataset.csv")

print("Dataset Shape:", data.shape)
print(data.head())

# =====================================================
# STEP 3 : HANDLE MISSING VALUES
# =====================================================

print("\nHandling Missing Values...")

imputer = SimpleImputer(strategy="mean")

numeric_cols = data.select_dtypes(include=['float64','int64']).columns

data[numeric_cols] = imputer.fit_transform(data[numeric_cols])

data.fillna("Unknown", inplace=True)

# =====================================================
# STEP 4 : ENCODE CATEGORICAL FEATURES
# =====================================================

print("\nEncoding Categorical Features...")

encoder = LabelEncoder()

categorical_cols = ["time_slot","food_item","food_category","weather_type"]

for col in categorical_cols:
    data[col] = encoder.fit_transform(data[col])

# =====================================================
# STEP 5 : FEATURE / TARGET SPLIT
# =====================================================

print("\nPreparing Features and Target...")

target = "quantity_sold"

X = data.drop(columns=["quantity_sold","date"])
y = data[target]

feature_names = X.columns

# =====================================================
# STEP 6 : TRAIN TEST SPLIT
# =====================================================

print("\nSplitting Dataset...")

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

# =====================================================
# STEP 7 : FEATURE SCALING
# =====================================================

print("\nScaling Features...")

scaler = StandardScaler()

X_train = scaler.fit_transform(X_train)
X_test = scaler.transform(X_test)

# =====================================================
# STEP 8 : MODEL TRAINING
# =====================================================

print("\nTraining Models...")

models = {

    "Linear Regression": LinearRegression(),

    "Random Forest": RandomForestRegressor(
        n_estimators=120,
        max_depth=12,
        random_state=42
    ),

    "Gradient Boosting": GradientBoostingRegressor()

}

best_model = None
best_score = -999
best_model_name = ""

# =====================================================
# STEP 9 : MODEL EVALUATION
# =====================================================

for name, model in models.items():

    print("\nTraining:", name)

    model.fit(X_train, y_train)

    predictions = model.predict(X_test)

    mae = mean_absolute_error(y_test, predictions)
    r2 = r2_score(y_test, predictions)

    print("MAE:", mae)
    print("R2 Score:", r2)

    # Save each model
    model_filename = f"models/{name.lower().replace(' ','_')}.pkl"
    joblib.dump(model, model_filename)

    print("Saved:", model_filename)

    if r2 > best_score:
        best_score = r2
        best_model = model
        best_model_name = name

# =====================================================
# STEP 10 : SAVE BEST MODEL
# =====================================================

joblib.dump(best_model, "models/best_model.pkl")

print("\nBest Model Selected:", best_model_name)
print("Best R2 Score:", best_score)

# =====================================================
# STEP 11 : FEATURE IMPORTANCE (VISUALIZATION)
# =====================================================

print("\nGenerating Feature Importance Graph...")

# only tree models support importance
if hasattr(best_model, "feature_importances_"):

    importance = best_model.feature_importances_

    feature_importance = pd.DataFrame({
        "feature": feature_names,
        "importance": importance
    })

    feature_importance = feature_importance.sort_values(
        by="importance",
        ascending=False
    )

    print(feature_importance.head(10))

    plt.figure(figsize=(10,6))

    plt.barh(
        feature_importance["feature"][:10],
        feature_importance["importance"][:10]
    )

    plt.xlabel("Importance Score")
    plt.ylabel("Features")
    plt.title("Top Features Affecting Food Demand")

    plt.gca().invert_yaxis()

    plt.tight_layout()

    plt.savefig("models/feature_importance.png")

    plt.show()

print("\nTraining Completed Successfully")