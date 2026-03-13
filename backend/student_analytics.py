from firebase_connect import db
import pandas as pd

def student_behavior():

    orders_ref = db.collection("orders")
    docs = orders_ref.stream()

    data = []

    for doc in docs:
        data.append(doc.to_dict())

    df = pd.DataFrame(data)

    popular_food = df["food_item"].value_counts().head(5)

    peak_time = df["time_slot"].value_counts().idxmax()

    return {

        "most_popular_food": popular_food.to_dict(),
        "peak_order_time": peak_time,
        "total_orders": len(df)

    }from firebase_connect import db
import pandas as pd

def student_behavior():

    orders_ref = db.collection("orders")
    docs = orders_ref.stream()

    data = []

    for doc in docs:
        data.append(doc.to_dict())

    df = pd.DataFrame(data)

    popular_food = df["food_item"].value_counts().head(5)

    peak_time = df["time_slot"].value_counts().idxmax()

    return {

        "most_popular_food": popular_food.to_dict(),
        "peak_order_time": peak_time,
        "total_orders": len(df)

    }