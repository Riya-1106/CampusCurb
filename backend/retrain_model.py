from pprint import pprint

from ml_pipeline import train_models


if __name__ == "__main__":
    print("Starting model retraining...")
    metrics = train_models()
    print("Model retraining completed")
    pprint(metrics)
