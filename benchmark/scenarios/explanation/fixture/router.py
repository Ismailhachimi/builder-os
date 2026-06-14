from service import create_note, list_notes


def dispatch(method: str, path: str, payload: dict) -> dict:
    if method == "GET" and path == "/notes":
        return {"status": 200, "body": list_notes()}
    if method == "POST" and path == "/notes":
        return {"status": 201, "body": create_note(payload["text"])}
    return {"status": 404, "body": {"error": "not found"}}
