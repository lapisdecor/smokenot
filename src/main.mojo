# Copyright (C) 2026 Luís Louro
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Licensed under the GNU General Public License, version 3 or later. The full
# text is in LICENSE.

"""Smokenot: a small offline quit-smoking companion.

The window, the pages and the callbacks live in `ui.app`; this file is only the
entry point, so that everything GTK related is in one place.
"""

from ui import app


def main() raises:
    var status = app.run()
    if status != 0:
        print("smokenot exited with status", status)
