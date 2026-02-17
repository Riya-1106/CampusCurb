import sqlite3

conn = sqlite3.connect("database.db")
cursor = conn.cursor()

# -----------------------------------
# USERS TABLE
# -----------------------------------
cursor.execute("""
CREATE TABLE IF NOT EXISTS users (
    user_id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT,
    department TEXT,
    year INTEGER,
    is_hosteller INTEGER
)
""")

# -----------------------------------
# MENU TABLE
# -----------------------------------
cursor.execute("""
CREATE TABLE IF NOT EXISTS menu (
    menu_id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT,
    time_slot TEXT,
    food_item TEXT,
    food_category TEXT,
    price REAL,
    is_veg INTEGER
)
""")

# -----------------------------------
# DAILY RESPONSES TABLE
# -----------------------------------
cursor.execute("""
CREATE TABLE IF NOT EXISTS daily_responses (
    response_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    date TEXT,
    time_slot TEXT,
    is_coming INTEGER,
    selected_dish TEXT,
    notification_clicked INTEGER,
    response_time TEXT,
    FOREIGN KEY(user_id) REFERENCES users(user_id)
)
""")

# -----------------------------------
# DISH CLICK TRACKING
# -----------------------------------
cursor.execute("""
CREATE TABLE IF NOT EXISTS dish_clicks (
    click_id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT,
    time_slot TEXT,
    food_item TEXT,
    click_count INTEGER
)
""")

# -----------------------------------
# PREDICTION LOG TABLE
# -----------------------------------
cursor.execute("""
CREATE TABLE IF NOT EXISTS prediction_log (
    prediction_id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT,
    time_slot TEXT,
    food_item TEXT,
    confirmed_count INTEGER,
    predicted_quantity INTEGER,
    buffer_added INTEGER
)
""")

# -----------------------------------
# ACTUAL SALES DATA
# -----------------------------------
cursor.execute("""
CREATE TABLE IF NOT EXISTS actual_food_data (
    actual_id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT,
    time_slot TEXT,
    food_item TEXT,
    quantity_prepared INTEGER,
    quantity_sold INTEGER,
    quantity_wasted INTEGER
)
""")

conn.commit()
conn.close()

print("✅ Large Database Initialized Successfully")
