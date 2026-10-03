# Copyright (C) 2026 Luís Louro
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Licensed under the GNU General Public License, version 3 or later. The full
# text is in LICENSE.

from model.milestones import (
    all,
    count,
    elapsed_label,
    is_reached,
    next_index,
    next_seconds_remaining,
    progress,
    reached_count,
    summary_key,
)
from model.stats import SECONDS_PER_DAY, SECONDS_PER_HOUR, SECONDS_PER_MINUTE
from tests.harness import Harness, begin_suite, check, check_eq, check_float, check_int


def run(mut h: Harness):
    begin_suite(h, "model.milestones")

    var list = all()
    var n = len(list)
    check_int(h, Int64(n), Int64(14), "milestone count")
    check_int(h, Int64(count()), Int64(14), "count helper agrees")

    # ---- ordering and labels -------------------------------------------

    var ordered = True
    var labelled = True
    var i = 0
    while i < n:
        if i > 0 and list[i].seconds <= list[i - 1].seconds:
            ordered = False
        if list[i].key.byte_length() == 0:
            labelled = False
        i += 1
    check(h, ordered, "milestones are in ascending order")
    check(h, labelled, "every milestone has both labels")
    check_eq(h, list[0].key, "milestone_20min", "first milestone is 20 minutes")
    check_int(h, list[0].seconds, Int64(20) * SECONDS_PER_MINUTE, "20 minutes in seconds")
    check_int(h, list[1].seconds, Int64(8) * SECONDS_PER_HOUR, "8 hours in seconds")
    check_int(h, list[2].seconds, SECONDS_PER_DAY, "24 hours is one day")
    check_int(h, list[13].seconds, Int64(15) * SECONDS_PER_DAY * Int64(365), "15 years")

    check_eq(h, elapsed_label(Int64(1200)), "20 min", "label minutes")
    check_eq(h, elapsed_label(Int64(28800)), "8 h", "label hours")
    check_eq(h, elapsed_label(Int64(86400)), "1 d", "label days")
    check_eq(h, elapsed_label(Int64(86400 * 30)), "1 mo", "label months")
    check_eq(h, elapsed_label(Int64(86400 * 365)), "1 y", "label years")
    check_eq(h, elapsed_label(Int64(60)), "1 min", "label one minute")

    # ---- progress -------------------------------------------------------

    check_int(h, Int64(reached_count(Int64(0))), Int64(0), "nothing reached at the start")
    check_int(h, Int64(reached_count(Int64(1200 - 1))), Int64(0), "one second short")
    check_int(h, Int64(reached_count(Int64(1200))), Int64(1), "20 minutes reached")
    check_int(h, Int64(reached_count(Int64(86400))), Int64(3), "one day reaches three")
    check_int(h, Int64(reached_count(Int64(86400 * 400))), Int64(11), "400 days passes the one year mark")
    check_int(h, Int64(reached_count(Int64(86400 * 86400))), Int64(14), "everything reached")

    check_int(h, Int64(next_index(Int64(0))), Int64(0), "next is the first")
    check_int(h, Int64(next_index(Int64(1199))), Int64(0), "next is still the first")
    check_int(h, Int64(next_index(Int64(1200))), Int64(1), "next moves on")
    check_int(h, Int64(next_index(Int64(86400))), Int64(3), "next after a day")
    check_int(h, Int64(next_index(Int64(86400 * 86400))), Int64(-1), "next is none at the end")

    check(h, not is_reached(0, Int64(1199)), "not reached one second short")
    check(h, is_reached(0, Int64(1200)), "reached on the second")
    check(h, not is_reached(-1, Int64(999999)), "negative index is not reached")
    check(h, not is_reached(14, Int64(999999)), "index past the end is not reached")

    check_float(h, progress(Int64(0)), Float64(0.0), "no progress at the start")
    check_float(h, progress(Int64(1200)), Float64(0.0), "progress resets at a milestone")
    check_float(h, progress(Int64(86400 * 86400)), Float64(1.0), "full progress at the end")
    check(h, progress(Int64(600)) > Float64(0.0), "some progress halfway to 20 minutes")
    check(h, progress(Int64(1200)) < Float64(1.0), "not finished at the first milestone")

    # Halfway between 20 minutes and 8 hours is half progress.
    var halfway = Int64(1200) + Int64(28800 - 1200) // Int64(2)
    var expected = progress(halfway)
    check(h, expected > Float64(0.4) and expected < Float64(0.6), "midpoint progress")

    check_int(h, next_seconds_remaining(Int64(0)), Int64(1200), "time to first milestone")
    check_int(h, next_seconds_remaining(Int64(1200)), Int64(28800 - 1200), "time to second")
    check_int(h, next_seconds_remaining(Int64(86400 * 86400)), Int64(0), "no time left at the end")

    check_eq(h, summary_key(Int64(0)), "milestone_20min", "summary before the start")
    check_eq(h, summary_key(Int64(86400)), "milestone_48h", "summary after a day")
    check_eq(h, summary_key(Int64(86400 * 86400)), "", "summary at the end")
