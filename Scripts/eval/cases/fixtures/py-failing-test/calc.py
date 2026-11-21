def add(a, b):
    return a + b


def discount(price, percent):
    # Bug kept on purpose for the eval: percent is applied twice.
    return price - price * percent / 100 * 2
