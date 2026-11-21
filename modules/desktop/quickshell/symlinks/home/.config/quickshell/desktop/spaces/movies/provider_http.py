"""Retry-After handling shared by the media API workers."""

import math
import os
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from contextlib import closing
from datetime import timezone
from email.utils import parsedate_to_datetime
from pathlib import Path

_RUNTIME = os.environ.get('XDG_RUNTIME_DIR')
_STATE = Path(_RUNTIME) / 'quickshell-media-retry.sqlite' if _RUNTIME else None
_lock = threading.Lock()
_deadlines = {}


def _retry_until(value, now):
    value = (value or '').strip()
    if value.isascii() and value.isdecimal():
        return now + float(value)
    try:
        date = parsedate_to_datetime(value)
        if date.tzinfo is None:
            date = date.replace(tzinfo=timezone.utc)
        return date.timestamp()
    except (ValueError, OverflowError, OSError):
        return 0


def _deadline(host, now, retry_until=0):
    with _lock:
        deadline = max(retry_until, _deadlines.get(host, 0))
        try:
            if _STATE and (retry_until or _STATE.is_file()):
                with closing(sqlite3.connect(_STATE, timeout=1)) as db, db:
                    if retry_until:
                        db.execute(
                            'CREATE TABLE IF NOT EXISTS retry_after '
                            '(host TEXT PRIMARY KEY, deadline REAL NOT NULL)'
                        )
                        db.execute(
                            'DELETE FROM retry_after WHERE deadline <= ?', (now,)
                        )
                        db.execute(
                            'INSERT INTO retry_after VALUES (?, ?) '
                            'ON CONFLICT(host) DO UPDATE SET '
                            'deadline = max(deadline, excluded.deadline)',
                            (host, deadline),
                        )
                    row = db.execute(
                        'SELECT deadline FROM retry_after WHERE host = ?', (host,)
                    ).fetchone()
                    if row:
                        deadline = max(deadline, row[0])
        except (OSError, sqlite3.Error):
            # An unavailable runtime directory must not disable media APIs.
            pass
        if deadline > now:
            _deadlines[host] = deadline
        else:
            _deadlines.pop(host, None)
        return deadline


def open_provider(request, *, timeout, error_type, name=None):
    """Open one request or report how long its host has asked us to wait."""
    host = urllib.parse.urlsplit(request.full_url).hostname
    name = name or host
    now = time.time()
    remaining = _deadline(host, now) - now
    if remaining > 0:
        raise error_type(
            f'{name} asked clients to wait {math.ceil(remaining)} s before retrying.'
        )
    try:
        return urllib.request.urlopen(request, timeout=timeout)
    except urllib.error.HTTPError as error:
        if error.code in (429, 503) and error.headers:
            now = time.time()
            deadline = _retry_until(error.headers.get('Retry-After'), now)
            if math.isfinite(deadline) and deadline > now:
                remaining = _deadline(host, now, deadline) - now
                error.close()
                raise error_type(
                    f'{name} returned HTTP {error.code}. Try again in {math.ceil(remaining)} s.'
                ) from None
        raise
