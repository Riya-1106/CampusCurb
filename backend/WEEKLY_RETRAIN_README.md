# Weekly Retraining Setup

This directory contains scripts for **continuous learning** - automatic weekly model retraining with fresh data.

## Files

- `weekly_retrain.py`: Main Python script that runs the continuous learning pipeline
- `weekly_retrain.bat`: Windows batch file for Task Scheduler

## Continuous Learning Flow

```
Firebase Orders → firebase_to_dataset.py → Append to existing dataset → Delete old model → train.py → New model saved
```

## What it does

1. **Download new dataset**: Fetches latest orders from Firebase
2. **Merge with old dataset**: Appends new data to existing `models/food_demand_dataset.csv` (no duplicates)
3. **Delete old model**: Removes `models/best_model.pkl` for fresh training
4. **Retrain model**: Trains on expanded dataset with more data

## Setup Weekly Cron Job

### Windows (Task Scheduler)

1. Open Task Scheduler
2. Create a new task
3. Set trigger: Weekly, every 1 week
4. Set action: Start a program
   - Program: `C:\path\to\CampusCurb\backend\weekly_retrain.bat`
   - Start in: `C:\path\to\CampusCurb\backend`
5. Set to run whether user is logged on or not

### Linux/Mac (Cron)

Add to crontab (`crontab -e`):

```
# Weekly on Sunday at 2 AM
0 2 * * 0 cd /path/to/CampusCurb/backend && python weekly_retrain.py
```

## Manual Run

```bash
python weekly_retrain.py
```

Or via API: `POST /retrain`

## Benefits

- **Continuous Learning**: Model improves over time with more data
- **No Data Loss**: Historical data is preserved and expanded
- **Fresh Training**: Old model deleted to prevent bias from stale weights
- **Scalable**: Dataset grows, predictions get more accurate