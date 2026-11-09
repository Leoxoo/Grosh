"""How tools/check and tools/check-logs fit a message on one printed line."""


def first_line(text):
    """The first line of text that is not blank, stripped."""
    for line in (text or "").splitlines():
        if line.strip():
            return line.strip()
    return ""


def one_line(text):
    """Every line of text joined into one, with each run of spaces as a single space."""
    return " ".join(str(text).split())


def shorten(text, limit, more=False):
    """text cut to limit characters. A closing … shows there was more: text was cut, or more says so."""
    if len(text) > limit:
        text, more = text[:limit].rstrip(), True
    return text + " …" if more else text
