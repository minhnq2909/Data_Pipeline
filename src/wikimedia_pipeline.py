from __future__ import annotations

import hashlib
import json
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Iterable

import psycopg2
from psycopg2.extras import Json, execute_values
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


@dataclass
class LoadStats:
    fetched: int = 0
    inserted: int = 0
    duplicates: int = 0
    quarantined: int = 0
    outside_window: int = 0
    pages: int = 0

    def add(self, other: "LoadStats") -> None:
        self.fetched += other.fetched
        self.inserted += other.inserted
        self.duplicates += other.duplicates
        self.quarantined += other.quarantined
        self.outside_window += other.outside_window
        self.pages += other.pages


def parse_utc(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError(f"Timestamp has no timezone: {value}")
    return parsed.astimezone(timezone.utc)


def require_env(name: str, default: str | None = None) -> str:
    value = os.getenv(name, default)
    if value is None or not value.strip():
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def build_session(user_agent: str) -> requests.Session:
    retry = Retry(
        total=5,
        connect=5,
        read=5,
        status=5,
        backoff_factor=1.0,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=frozenset({"GET"}),
        respect_retry_after_header=True,
    )
    adapter = HTTPAdapter(max_retries=retry)
    session = requests.Session()
    session.headers.update({"User-Agent": user_agent})
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    return session


def get_connection():
    return psycopg2.connect(
        host=require_env("WAREHOUSE_HOST", "warehouse"),
        port=int(require_env("WAREHOUSE_PORT", "5432")),
        dbname=require_env("WAREHOUSE_DB", "dataflow"),
        user=require_env("WAREHOUSE_USER", "dataflow"),
        password=require_env("WAREHOUSE_PASSWORD"),
        connect_timeout=15,
        application_name="wikimedia_recentchanges_extract",
    )


def record_fingerprint(
    record: dict[str, Any],
    window_start: datetime,
    window_end: datetime,
) -> str:
    canonical = json.dumps(
        record,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    raw = f"{canonical}|{window_start.isoformat()}|{window_end.isoformat()}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def quarantine(
    cursor,
    record: dict[str, Any],
    error_type: str,
    error_message: str,
    window_start: datetime,
    window_end: datetime,
) -> int:
    cursor.execute(
        """
        INSERT INTO raw.wikimedia_recentchanges_errors (
            _error_fingerprint,
            _raw,
            _error_type,
            _error_message,
            _window_start,
            _window_end
        )
        VALUES (%s, %s, %s, %s, %s, %s)
        ON CONFLICT (_error_fingerprint) DO NOTHING
        RETURNING _error_id
        """,
        (
            record_fingerprint(record, window_start, window_end),
            Json(record),
            error_type,
            error_message[:2000],
            window_start,
            window_end,
        ),
    )
    return 1 if cursor.fetchone() else 0


def validate_record(
    record: dict[str, Any],
    window_start: datetime,
    window_end: datetime,
) -> tuple[bool, str | None, str | None, bool]:
    try:
        int(record["rcid"])
    except (KeyError, TypeError, ValueError) as exc:
        return False, "invalid_natural_key", str(exc), False

    try:
        event_time = parse_utc(str(record["timestamp"]))
    except (KeyError, TypeError, ValueError) as exc:
        return False, "invalid_timestamp", str(exc), False

    outside_window = not (window_start <= event_time < window_end)
    return True, None, None, outside_window


def load_page(
    connection,
    records: Iterable[dict[str, Any]],
    window_start: datetime,
    window_end: datetime,
) -> LoadStats:
    stats = LoadStats()
    valid_rows: list[tuple[Json, datetime, datetime]] = []

    with connection.cursor() as cursor:
        for record in records:
            stats.fetched += 1
            is_valid, error_type, error_message, outside_window = validate_record(
                record,
                window_start,
                window_end,
            )

            if not is_valid:
                stats.quarantined += quarantine(
                    cursor,
                    record,
                    error_type or "invalid_record",
                    error_message or "Unknown validation error",
                    window_start,
                    window_end,
                )
                continue

            # Filtering to the assigned [start, end) interval is extraction logic,
            # not a transformation. The original payload is still written unchanged.
            if outside_window:
                stats.outside_window += 1
                continue

            valid_rows.append((Json(record), window_start, window_end))

        if valid_rows:
            inserted_ids = execute_values(
                cursor,
                """
                INSERT INTO raw.wikimedia_recentchanges (
                    _raw,
                    _window_start,
                    _window_end
                )
                VALUES %s
                ON CONFLICT DO NOTHING
                RETURNING _raw_id
                """,
                valid_rows,
                template="(%s, %s, %s)",
                page_size=500,
                fetch=True,
            )
            stats.inserted = len(inserted_ids)
            stats.duplicates = len(valid_rows) - stats.inserted

    connection.commit()
    return stats


def extract_window(
    api_url: str,
    user_agent: str,
    window_start: datetime,
    window_end: datetime,
    max_pages: int,
) -> LoadStats:
    if window_start >= window_end:
        raise ValueError("WINDOW_START must be earlier than WINDOW_END")

    # RecentChanges on Wikimedia retains about 30 days.
    if datetime.now(timezone.utc) - window_start > timedelta(days=30):
        raise ValueError(
            "WINDOW_START is older than Wikimedia RecentChanges retention "
            "(approximately 30 days). Choose a more recent backfill range."
        )

    session = build_session(user_agent)
    params: dict[str, Any] = {
        "action": "query",
        "format": "json",
        "formatversion": "2",
        "list": "recentchanges",
        "rcstart": window_start.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "rcend": window_end.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "rcdir": "newer",
        "rclimit": "max",
        "rctype": "edit|new|log|categorize|external",
        "rcprop": (
            "title|ids|sizes|flags|user|userid|timestamp|comment|loginfo|tags"
        ),
        "continue": "",
    }

    total = LoadStats()
    connection = get_connection()

    try:
        for page_number in range(1, max_pages + 1):
            response = session.get(api_url, params=params, timeout=(10, 90))
            response.raise_for_status()
            payload = response.json()

            if "error" in payload:
                raise RuntimeError(
                    "Wikimedia API error: "
                    + json.dumps(payload["error"], ensure_ascii=False)
                )

            records = payload.get("query", {}).get("recentchanges", [])
            page_stats = load_page(
                connection,
                records,
                window_start,
                window_end,
            )
            page_stats.pages = 1
            total.add(page_stats)

            print(
                json.dumps(
                    {
                        "page": page_number,
                        "page_fetched": page_stats.fetched,
                        "page_inserted": page_stats.inserted,
                        "page_duplicates": page_stats.duplicates,
                        "page_quarantined": page_stats.quarantined,
                        "page_outside_window": page_stats.outside_window,
                    },
                    ensure_ascii=False,
                ),
                flush=True,
            )

            continuation = payload.get("continue")
            if not continuation:
                break

            params.update(continuation)
        else:
            raise RuntimeError(
                f"Reached WIKIMEDIA_MAX_PAGES={max_pages}; "
                "pagination may be incomplete."
            )
    finally:
        connection.close()
        session.close()

    return total


def main() -> int:
    window_start = parse_utc(require_env("WINDOW_START"))
    window_end = parse_utc(require_env("WINDOW_END"))

    stats = extract_window(
        api_url=require_env(
            "WIKIMEDIA_API_URL",
            "https://vi.wikipedia.org/w/api.php",
        ),
        user_agent=require_env("WIKIMEDIA_USER_AGENT"),
        window_start=window_start,
        window_end=window_end,
        max_pages=int(require_env("WIKIMEDIA_MAX_PAGES", "5000")),
    )

    print(
        json.dumps(
            {
                "window_start": window_start.isoformat(),
                "window_end": window_end.isoformat(),
                "fetched": stats.fetched,
                "inserted": stats.inserted,
                "duplicates": stats.duplicates,
                "quarantined": stats.quarantined,
                "outside_window": stats.outside_window,
                "pages": stats.pages,
            },
            ensure_ascii=False,
        ),
        flush=True,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(
            json.dumps(
                {
                    "status": "failed",
                    "error_type": type(exc).__name__,
                    "error": str(exc),
                },
                ensure_ascii=False,
            ),
            file=sys.stderr,
            flush=True,
        )
        raise
