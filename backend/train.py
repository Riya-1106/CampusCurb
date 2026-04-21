from pprint import pprint

from ml_pipeline import train_models


if __name__ == "__main__":
    metrics = train_models()
    print("Training completed successfully")
    pprint(metrics)
