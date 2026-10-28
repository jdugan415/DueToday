import pytest

from app.ratelimit import ALL_LIMITERS


@pytest.fixture(autouse=True)
def _reset_rate_limits():
    """Rate-limit state is process-global; isolate every test from the others."""
    for limiter in ALL_LIMITERS:
        limiter.reset()
    yield
    for limiter in ALL_LIMITERS:
        limiter.reset()
