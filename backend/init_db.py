import sqlite3

conn = sqlite3.connect("database.db")
cursor = conn.cursor()

# USERS
cursor.execute("""
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT,
    email TEXT UNIQUE,
    password TEXT,
    role TEXT,
    campus_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
""")

# CAMPUSES
cursor.execute("""
CREATE TABLE IF NOT EXISTS campuses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    campus_name TEXT,
    location TEXT
)
""")

# FOOD ITEMS
cursor.execute("""
CREATE TABLE IF NOT EXISTS food_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    food_name TEXT,
    category TEXT,
    price REAL,
    is_active INTEGER DEFAULT 1
)
""")

# DAILY MENU
cursor.execute("""
CREATE TABLE IF NOT EXISTS daily_menu (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    campus_id INTEGER,
    date TEXT,
    food_item_id INTEGER,
    timing_slot TEXT
)
""")

# STUDENT RESPONSES
cursor.execute("""
CREATE TABLE IF NOT EXISTS student_responses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    food_item_id INTEGER,
    date TEXT,
    will_attend INTEGER,
    clicked_food INTEGER,
    submitted_response INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
""")

# ACTUAL SALES
cursor.execute("""
CREATE TABLE IF NOT EXISTS actual_sales (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    campus_id INTEGER,
    food_item_id INTEGER,
    date TEXT,
    quantity_prepared INTEGER,
    quantity_sold INTEGER,
    leftover_quantity INTEGER
)
""")

# WEATHER DATA
cursor.execute("""
CREATE TABLE IF NOT EXISTS weather_data (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    campus_id INTEGER,
    date TEXT,
    temperature REAL,
    rainfall REAL
)
""")

# EVENT CALENDAR
cursor.execute("""
CREATE TABLE IF NOT EXISTS event_calendar (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    campus_id INTEGER,
    date TEXT,
    is_exam_day INTEGER,
    is_event_day INTEGER,
    is_holiday INTEGER,
    description TEXT
)
""")

# REWARDS
cursor.execute("""
CREATE TABLE IF NOT EXISTS rewards (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    points INTEGER DEFAULT 0,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
""")

# FOOD FEEDBACK
cursor.execute("""
CREATE TABLE IF NOT EXISTS food_feedback (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    food_item_id INTEGER,
    rating INTEGER,
    comment TEXT,
    date TEXT
)
""")

# PREDICTIONS TABLE
cursor.execute("""
CREATE TABLE IF NOT EXISTS predictions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    campus_id INTEGER,
    food_item_id INTEGER,
    date TEXT,
    base_prediction REAL,
    buffer_added INTEGER,
    final_prediction INTEGER,
    actual_sold INTEGER,
    error_value REAL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
""")

conn.commit()
conn.close()

print("✅ Database initialized successfully!")
