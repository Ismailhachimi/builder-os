#!/bin/zsh
python3 -m unittest discover -s tests -v
python3 - <<'PY'
from tickets import group_by_status

tickets = [
    {"id": 1, "status": "open"},
    {"id": 2, "status": "closed"},
    {"id": 3, "status": "open"},
]
assert group_by_status(tickets) == {
    "open": [tickets[0], tickets[2]],
    "closed": [tickets[1]],
}
for invalid in ({}, {"status": ""}, {"status": 4}):
    try:
        group_by_status([invalid])
    except ValueError:
        pass
    else:
        raise AssertionError(f"expected ValueError for {invalid!r}")
PY
