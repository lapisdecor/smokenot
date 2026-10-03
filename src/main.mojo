"""Smokenot: a small offline quit-smoking companion.

The window, the pages and the callbacks live in `ui.app`; this file is only the
entry point, so that everything GTK related is in one place.
"""

from ui import app


def main() raises:
    var status = app.run()
    if status != 0:
        print("smokenot exited with status", status)
