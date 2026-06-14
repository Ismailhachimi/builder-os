_notes: list[dict] = []


def list_notes() -> list[dict]:
    return list(_notes)


def create_note(text: str) -> dict:
    note = {"id": len(_notes) + 1, "text": text}
    _notes.append(note)
    return note
