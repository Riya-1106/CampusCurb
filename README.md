# ML‑Based Smart Canteen Management System
### Demand Forecasting and Food Waste Reduction

---

# Overview
The **ML‑Based Smart Canteen Management System** is a mobile application designed to optimize food preparation in college canteens using **Machine Learning demand forecasting**.

The system predicts food demand based on historical order data, student behavior patterns, and contextual features such as day, time slot, and weather conditions. Using these predictions, the system recommends the optimal quantity of food to prepare, helping reduce **food wastage** and improve **canteen efficiency**.

The project also provides a **multi‑role platform** including students, faculty, canteen operators, and administrators to manage food ordering, inventory, and analytics within the campus.

---

# Problem Statement

College canteens often face the following problems:

- Over‑preparation of food leading to **food wastage**
- Under‑preparation leading to **food shortages**
- Lack of **data‑driven decision making**
- No centralized platform for **food ordering and monitoring**
- Difficulty tracking **canteen demand trends**

This project solves these problems using **machine learning‑based demand prediction** and a **centralized mobile platform**.

---

# Project Objectives

- Predict food demand using **Machine Learning**
- Reduce **food wastage** through optimized preparation
- Provide **real‑time analytics** for canteen operators
- Implement **role‑based access system**
- Track student food ordering behavior
- Provide **reward and engagement system**
- Enable **faculty pay‑later billing system**
- Allow **admin approval for menu items**
- Enable **inter‑college food sharing system**

---

# Key Features

## Machine Learning Demand Forecasting

The ML model predicts future food demand using historical order data and contextual features.

Example Output:

| Food Item | Predicted Demand | Suggested Preparation |
|-----------|-----------------|----------------------|
| Burger | 120 | 132 |
| Pizza | 95 | 104 |
| Sandwich | 70 | 77 |

Suggested preparation includes a **safety margin** to avoid shortages.

---

## Food Waste Analytics

The system tracks:

- Quantity Prepared
- Quantity Sold
- Quantity Wasted
- Waste Percentage

Example:
- Total Prepared: 5000 meals
- Total Sold: 4200 meals
- Total Wasted: 800 meals
- Waste Percentage: 16%
The system also estimates **waste reduction achieved through ML predictions**.

---

# Multi‑Role Access System

The platform supports multiple user roles.

## Student

Students can:

- View daily menu
- Order food
- Mark attendance
- Earn reward points
- View leaderboard
- Redeem rewards

---

## Faculty

Faculty members have the same features as students plus:

- **Pay Later option**
- Weekly or monthly payment notifications

---

## Canteen Operator

Canteen staff can:

- Upload menu items
- View demand predictions
- Monitor inventory
- View waste analytics
- Track order statistics

Menu items uploaded by the canteen must be **approved by admin before becoming visible**.

---

## Admin Panel

Admin controls the system and can:

- Approve or reject menu items
- Create student and faculty accounts
- Monitor analytics and waste reports
- Approve inter‑college food exchange requests
- Manage system operations

---

## Inter‑College Portal

Colleges can share surplus food.

Example scenario:
- College A → 50 sandwiches remaining
- College B → requests food
- Admin → approves transfer
This feature helps reduce **large‑scale food waste across institutions**.

---

# Machine Learning Pipeline

The ML workflow consists of the following steps.

## 1 Dataset Generation

Historical order data is converted into a dataset using backend scripts.

Example features:
- date
- day_of_week
- week_of_year
- month
- time_slot
- is_weekend
- is_exam_day
- food_item
- food_category
- price
- portion_size
- prev_day_sales
- avg_last_7_days_sales
- sales_trend_weekly
- quantity_prepared
- quantity_sold
- quantity_wasted
- weather_type
- temperature

---

## 2 Data Preprocessing

The preprocessing stage includes:

- Handling missing values
- Feature encoding
- Normalization
- Feature selection

---

## 3 Model Training

Multiple machine learning algorithms are trained and compared:

- Random Forest
- Gradient Boosting
- Linear Regression

The model with the best performance is selected.

---

## 4 Feature Importance Analysis

Feature importance visualization helps understand which factors affect food demand the most.

Example influential features:

- Time slot
- Day of week
- Previous sales
- Weather conditions

---

## 5 Prediction

The trained model predicts demand for each food item.

Example:
- Predicted Demand: 120
- Suggested Preparation: 132

---

## 6 Prediction Monitoring

The system logs predictions and actual sales in Firebase.

Example log:
- Food Item: Burger
- Predicted Demand: 120
- Actual Sales: 115
- Prediction Error: 5

This helps evaluate **model accuracy over time**.

---

## 7 Continuous Model Retraining

The model can be retrained periodically using newly collected data.

Process:
<img width="500" height="273" alt="Gemini_Generated_Image_anvb50anvb50anvb" src="https://github.com/user-attachments/assets/faba2b6a-8dba-4759-8c70-a8bab7f9940c" />

---

# System Architecture
<img width="500" height="273" alt="Gemini_Generated_Image_usjzlfusjzlfusjz" src="https://github.com/user-attachments/assets/b3c51cfa-9c4f-4e7a-ab81-ac1c5addfd0a" />

---

# Technology Stack

## Frontend
Flutter (Mobile Application)

## Backend
Python

## Database
Firebase Firestore

## Authentication
Firebase Authentication

## Machine Learning Libraries

- Pandas
- NumPy
- Scikit‑learn
- Matplotlib

---

# Firebase Database Structure

Collections used:
- users
- menu
- menu_pending
- orders
- attendance
- rewards
- prediction_logs
- faculty_orders
- food_exchange

---

# Project Workflow
<img width="500" height="273" alt="Gemini_Generated_Image_sa98jfsa98jfsa98" src="https://github.com/user-attachments/assets/894ae725-6742-4da3-b08e-eeede95819a1" />

---

# Benefits of the System

- Reduces **food wastage**
- Improves **canteen efficiency**
- Enables **data‑driven decision making**
- Provides **real‑time analytics**
- Improves **student engagement through rewards**
- Enables **smart food demand forecasting**

---

# Future Enhancements

Possible improvements include:

- Advanced time‑series forecasting models
- Real‑time demand prediction dashboard
- IoT integration for inventory monitoring
- Multi‑campus deployment
- Enhanced analytics visualization

---

# Conclusion

The **ML‑Based Smart Canteen Management System** demonstrates how machine learning can be applied to real‑world problems such as food demand prediction and waste reduction.

By combining **mobile technology, cloud databases, and machine learning**, the system provides an intelligent platform for managing canteen operations efficiently while promoting sustainability.
