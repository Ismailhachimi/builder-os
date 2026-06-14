def retry_delays(attempts: int, base_seconds: int = 1) -> list[int]:
    """Return exponential delays before each retry."""
    return [base_seconds * (2**attempt) for attempt in range(1, attempts + 1)]
