# Copyright (C) 2026 Luís Louro
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Licensed under the GNU General Public License, version 3 or later. The full
# text is in LICENSE.

"""Developer self-test entry point.

Not shipped in the snap; build.sh runs this after every change to the logic
layer.
"""

from tests import (
    harness,
    test_i18n,
    test_json,
    test_milestones,
    test_state,
    test_stats,
    test_sys,
    test_text,
)


def main() raises:
    var h = harness.Harness()
    test_text.run(h)
    test_json.run(h)
    test_sys.run(h)
    test_i18n.run(h)
    test_stats.run(h)
    test_milestones.run(h)
    test_state.run(h)
    harness.finish(h)
