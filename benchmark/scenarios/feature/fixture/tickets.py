def open_ticket_ids(tickets: list[dict]) -> list[int]:
    return [ticket["id"] for ticket in tickets if ticket.get("status") == "open"]
