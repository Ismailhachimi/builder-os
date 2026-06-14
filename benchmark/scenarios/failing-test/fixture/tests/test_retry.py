import unittest

from retry import retry_delays


class RetryTests(unittest.TestCase):
    def test_delays_begin_at_base_and_double(self):
        self.assertEqual(retry_delays(4, 3), [3, 6, 12, 24])

    def test_zero_attempts(self):
        self.assertEqual(retry_delays(0), [])


if __name__ == "__main__":
    unittest.main()
