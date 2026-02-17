import sqlite3

conn = sqlite3.connect("database.db")

conn.execute("""
CREATE TABLE IF NOT EXISTS users (
    user_id INTEGER PRIMARY KEY,
    department TEXT,
    year INTEGER
)
""")

conn.execute("""
CREATE TABLE IF NOT EXISTS daily_responses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    date TEXT,
    is_coming INTEGER,
    selected_dishes TEXT
)
""")

conn.execute("""
CREATE TABLE IF NOT EXISTS food_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT,
    food_item TEXT,
    predicted_quantity INTEGER,
    actual_prepared INTEGER,
    actual_sold INTEGER
)
""")

conn.commit()
conn.close()

print("Database Initialized Successfully")
