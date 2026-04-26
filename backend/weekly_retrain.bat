@echo off
REM Weekly Retraining Batch Script
REM Run this weekly via Windows Task Scheduler

echo Starting weekly retraining at %DATE% %TIME% >> logs\weekly_retrain.log

REM Activate virtual environment if available in the backend folder
if exist .venv\Scripts\activate.bat (
  call .venv\Scripts\activate.bat
)

REM Run the retraining script
python weekly_retrain.py

REM Deactivate
if defined VIRTUAL_ENV call deactivate

echo Retraining completed at %DATE% %TIME% >> logs\weekly_retrain.log
