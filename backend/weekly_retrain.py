#!/usr/bin/env python3
"""Weekly retraining entrypoint for the shared ML pipeline."""

import logging
import os

from ml_pipeline import train_models

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
        print("Retraining model...")
        metrics = train_models()
        logging.info("Model retrained successfully")
        logging.info("Best model: %s", metrics.get("best_model_name", "Unknown"))
        print("Retraining completed successfully!")

    except Exception as e:
        error_msg = f"Retraining failed: {str(e)}"
        logging.error(error_msg)
        print(error_msg)
        raise

if __name__ == "__main__":
    run_retraining()
