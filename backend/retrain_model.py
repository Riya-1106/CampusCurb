import pandas as pd
import os
import subprocess

print("Starting weekly model retraining...")

# =========================================
# STEP 1 : LOAD EXISTING DATASET
# =========================================

dataset = pd.read_csv("models/food_demand_dataset.csv")

print("Existing dataset size:", dataset.shape)

# =========================================
# STEP 2 : LOAD NEW WEEK DATA
# =========================================

weekly_data = pd.read_csv("data/weekly_data.csv")

print("New weekly data:", weekly_data.shape)

# =========================================
# STEP 3 : MERGE DATASETS
# =========================================

updated_dataset = pd.concat([dataset, weekly_data], ignore_index=True)

print("Updated dataset size:", updated_dataset.shape)

# =========================================
# STEP 4 : SAVE UPDATED DATASET
# =========================================

updated_dataset.to_csv("models/food_demand_dataset.csv", index=False)

print("Dataset updated successfully")

# =========================================
# STEP 5 : DELETE OLD MODELS
# =========================================

models = [
    "models/best_model.pkl",
    "models/random_forest.pkl",
    "models/linear_regression.pkl",
    "models/gradient_boosting.pkl"
]

for model in models:
    if os.path.exists(model):
        os.remove(model)
        print("Deleted:", model)

# =========================================
# STEP 6 : RETRAIN MODEL
# =========================================

print("Retraining model...")

subprocess.run(["python", "train.py"])

print("Model retraining completed")