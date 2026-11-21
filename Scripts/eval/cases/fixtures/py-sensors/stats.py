"""Summarise sensor readings (eval fixture)."""
readings = [21.5, 19.5, 24.0, 23.0]


def summarize(values):
    if not values:
        raise ValueError("cannot summarize an empty dataset")
    return min(values), max(values), sum(values) / len(values)


low, high, avg = summarize(readings)
print(f"sensor summary: count={len(readings)} min={low} max={high} avg={avg:.2f}")
