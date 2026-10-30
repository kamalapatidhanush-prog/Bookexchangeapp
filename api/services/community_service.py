import uuid


def notify(cur, user_id, title, body, notif_type='system', ref_id=None):
    cur.execute(
        "INSERT INTO notifications (id, user_id, title, body, type, is_read, reference_id) "
        "VALUES (%s, %s, %s, %s, %s, 0, %s)",
        (str(uuid.uuid4()), user_id, title, body, notif_type, ref_id),
    )


def log_activity(cur, user_id, action_type, title, description, ref_id=None):
    cur.execute(
        "INSERT INTO activities (id, user_id, action_type, title, description, reference_id) "
        "VALUES (%s, %s, %s, %s, %s, %s)",
        (str(uuid.uuid4()), user_id, action_type, title, description, ref_id),
    )
