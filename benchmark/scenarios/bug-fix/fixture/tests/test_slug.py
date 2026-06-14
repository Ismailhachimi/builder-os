import unittest

from slug import slugify


class SlugifyTests(unittest.TestCase):
    def test_removes_punctuation_and_collapses_separators(self):
        self.assertEqual(slugify("  Hello,   Local Agent!  "), "hello-local-agent")

    def test_does_not_leave_edge_hyphens(self):
        self.assertEqual(slugify("---Already Sluggy---"), "already-sluggy")


if __name__ == "__main__":
    unittest.main()
