from firebase_connect import db

orders = db.collection("orders").stream()

for order in orders:
    print(order.to_dict())