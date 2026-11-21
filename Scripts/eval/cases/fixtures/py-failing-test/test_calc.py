import unittest

from calc import add, discount


class CalcTest(unittest.TestCase):
    def test_add(self):
        self.assertEqual(add(2, 3), 5)

    def test_discount(self):
        self.assertEqual(discount(200, 10), 180)


if __name__ == "__main__":
    unittest.main()
