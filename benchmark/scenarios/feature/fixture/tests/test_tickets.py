import unittest

from tickets import open_ticket_ids


class TicketTests(unittest.TestCase):
    def test_open_ticket_ids(self):
        tickets = [
            {"id": 1, "status": "closed"},
            {"id": 2, "status": "open"},
        ]
        self.assertEqual(open_ticket_ids(tickets), [2])


if __name__ == "__main__":
    unittest.main()
