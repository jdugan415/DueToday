"""Small in-process sliding-window rate limiter.

Good enough for a single free-tier instance: state lives in memory, so it
resets on restart and is per-process. If the API ever scales out, move this
to Redis (or put limits at the proxy).
"""

from __future__ import annotations

import os
import threading
import time
from collections import defaultdict, deque

from fastapi import HTTPException, Request


class RateLimiter:
    """FastAPI dependency allowing ``limit`` requests per ``window`` seconds per client."""

    def __init__(self, name: str, limit: int, window: float) -> None:
        self.name = name
        self.limit = limit
        self.window = window
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def __call__(self, request: Request) -> None:
        if self.limit <= 0:
            return
        key = client_key(request)
        now = time.monotonic()
        with self._lock:
            hits = self._hits[key]
            while hits and now - hits[0] >= self.window:
                hits.popleft()
            if len(hits) >= self.limit:
                retry_after = max(1, int(self.window - (now - hits[0])) + 1)
                raise HTTPException(
                    status_code=429,
                    detail="Too many requests. Please wait a moment and try again.",
                    headers={"Retry-After": str(retry_after)},
                )
            hits.append(now)

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()


def client_key(request: Request) -> str:
    # Uvicorn runs with --proxy-headers in Docker, so request.client is the
    # real client behind Render / Fly's proxy.
    return request.client.host if request.client else "unknown"


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, default))
    except ValueError:
        return default


# Limits are per client IP. Set an env var to 0 to disable that limiter.
parse_limiter = RateLimiter("parse", _env_int("RATE_LIMIT_PARSE_PER_MINUTE", 30), 60)
share_limiter = RateLimiter("share", _env_int("RATE_LIMIT_SHARE_PER_HOUR", 20), 3600)
lookup_limiter = RateLimiter("lookup", _env_int("RATE_LIMIT_LOOKUP_PER_MINUTE", 60), 60)

ALL_LIMITERS = (parse_limiter, share_limiter, lookup_limiter)
