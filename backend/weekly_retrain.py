#!/usr/bin/env python3
"""
Auto Retraining Script

This script automatically retrains the ML model by:
1. Fetching latest data from Firebase
2. Retraining the model

Run this script weekly via cron job or Windows Task Scheduler.
"""

import subprocess
import sys
import logging
import os
from datetime import datetime

# Ensure logs directory exists
os.makedirs("logs", exist_ok=True)

# Set up logging
logging.basicConfig(
    filename='logs/auto_retrain.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

def run_retraining():
    """Run the full retraining pipeline."""

    print("Starting auto retraining...")
    logging.info("Auto retraining started")

    try:
        # Step 1: Update dataset from Firebase
        print("Fetching data from Firebase...")
        result1 = subprocess.run(
            [sys.executable, "firebase_to_dataset.py"],
            capture_output=True,
            text=True,
            timeout=300  # 5 minutes timeout
        )

        if result1.returncode != 0:
            raise Exception(f"firebase_to_dataset.py failed: {result1.stderr}")

        logging.info("Dataset updated from Firebase")

        # Step 2.5: Delete old model for fresh training
        model_path = "models/best_model.pkl"
        if os.path.exists(model_path):
            os.remove(model_path)
            logging.info("Old model deleted")
            print("Old model deleted")

        # Step 3: Retrain the model
        print("Retraining model...")
        result2 = subprocess.run(
            [sys.executable, "train.py"],
            capture_output=True,
            text=True,
            timeout=600  # 10 minutes timeout
        )

        if result2.returncode != 0:
            raise Exception(f"train.py failed: {result2.stderr}")

        logging.info("Model retrained successfully")
        print("Retraining completed successfully!")

    except subprocess.TimeoutExpired:
        error_msg = "Retraining timed out"
        logging.error(error_msg)
        print(error_msg)
        sys.exit(1)

    except Exception as e:
        error_msg = f"Retraining failed: {str(e)}"
        logging.error(error_msg)
        print(error_msg)
        sys.exit(1)

if __name__ == "__main__":
    run_retraining()