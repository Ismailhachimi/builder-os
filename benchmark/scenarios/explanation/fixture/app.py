from router import dispatch


def handle(method: str, path: str, payload: dict | None = None) -> dict:
    return dispatch(method, path, payload or {})
