"""Send faculty pay-later reminders via Firebase Cloud Messaging.

Usage:
  /workspaces/CampusCurb/.venv/bin/python send_faculty_reminders.py --period weekly
  /workspaces/CampusCurb/.venv/bin/python send_faculty_reminders.py --period monthly
"""

import argparse
from datetime import datetime, timezone

from firebase_admin import messaging as firebase_messaging

from firebase_connect import db


def period_days(period: str) -> int:
    value = period.strip().lower()
    if value == 'weekly':
        return 7
    if value == 'monthly':
        return 30
    raise ValueError('period must be weekly or monthly')


def collect_pending(days: int) -> dict:
    now = datetime.now(timezone.utc)
    docs = db.collection('faculty_orders').where('payment_status', '==', 'pending').stream()

    grouped = {}
    for doc in docs:
        data = doc.to_dict() or {}
        created_raw = data.get('createdAt')

        include = True
        if created_raw:
            try:
                created_dt = datetime.fromisoformat(str(created_raw).replace('Z', '+00:00'))
                include = (now - created_dt).days < days
            except Exception:
                include = True

        if not include:
            continue

        faculty_id = data.get('faculty_id')
        if not faculty_id:
            continue

        grouped.setdefault(faculty_id, 0)
        grouped[faculty_id] += int(data.get('total_amount', 0) or 0)

    return grouped


def send(period: str) -> None:
    days = period_days(period)
    grouped = collect_pending(days)

    sent = 0
    skipped = 0

    for faculty_id, total in grouped.items():
        if total <= 0:
            continue

        user_doc = db.collection('users').document(faculty_id).get()
        user_data = user_doc.to_dict() if user_doc.exists else {}
        token = (user_data or {}).get('fcmToken')
        if not token:
            skipped += 1
            continue

        body = f'You have ₹{total} pending canteen payment this {period}.'
        message = firebase_messaging.Message(
            token=token,
            notification=firebase_messaging.Notification(
                title='Faculty Pay-Later Reminder',
                body=body,
            ),
            data={
                'type': 'faculty_pay_later_reminder',
                'faculty_id': faculty_id,
                'period': period,
                'total_pending': str(total),
            },
        )

        try:
            firebase_messaging.send(message)
            sent += 1
        except Exception:
            skipped += 1

    print(f'Finished. period={period} sent={sent} skipped={skipped}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--period', default='weekly', choices=['weekly', 'monthly'])
    args = parser.parse_args()
    send(args.period)
