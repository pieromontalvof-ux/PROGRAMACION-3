"""Bounded retries; all creation retries carry the same remote idempotency key."""
def next_retry(attempt, jitter):
    return min(300, 5 * 2 ** max(0, attempt - 1)) + min(30, max(0, jitter * 30))


def outcome(status):
    if status in (401, 403):
        return 'BLOQUEADO'
    if status in (408, 425, 429) or status >= 500:
        return 'REINTENTO'
    return 'RECHAZADO'
