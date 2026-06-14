import re


def slugify(value: str) -> str:
    """Return a lowercase, hyphen-separated URL slug."""
    value = value.strip().lower()
    return re.sub(r"\s+", "-", value)
