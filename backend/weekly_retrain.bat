@echo off
REM Weekly Retraining Batch Script
REM Run this weekly via Windows Task Scheduler

echo Starting weekly retraining at %DATE% %TIME% >> logs\weekly_retrain.log

REM Activate virtual environment
call ..\..\.venv\Scripts\activate.bat

REM Run the retraining script
python weekly_retrain.py

REM Deactivate
call deactivate

echo Retraining completed at %DATE% %TIME% >> logs\weekly_retrain.log

pause