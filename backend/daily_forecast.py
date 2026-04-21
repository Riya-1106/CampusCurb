from pprint import pprint

from ml_pipeline import FORECAST_OUTPUT_PATH, generate_forecast_rows


if __name__ == "__main__":
    rows = generate_forecast_rows(days_ahead=1)
    print(f"Tomorrow demand forecast generated at {FORECAST_OUTPUT_PATH}")
    pprint(rows)
