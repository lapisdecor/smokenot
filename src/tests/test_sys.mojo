# Copyright (C) 2026 Luís Louro
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Licensed under the GNU General Public License, version 3 or later. The full
# text is in LICENSE.

from lib import sys
from tests.harness import Harness, begin_suite, check, check_eq, check_int


def run(mut h: Harness) raises:
    begin_suite(h, "lib.sys")

    # ---- clock ---------------------------------------------------------

    var epoch = sys.now_epoch()
    check(h, epoch > Int64(1_600_000_000), "clock is after 2020")
    check(h, epoch < Int64(4_000_000_000), "clock is before 2100")
    check(h, sys.now_epoch() >= epoch, "clock does not go backwards")

    # UTC is exact everywhere, so the numbers below are fixed.
    var u = sys.utc_time(Int64(0))
    check_int(h, u.year, Int64(1970), "epoch zero is 1970")
    check_int(h, u.month, Int64(1), "epoch zero is January")
    check_int(h, u.day, Int64(1), "epoch zero is the first")
    check_int(h, u.hour, Int64(0), "epoch zero is midnight")
    check_int(h, u.weekday, Int64(4), "epoch zero was a Thursday")
    check_int(h, u.day_of_year, Int64(1), "epoch zero is day one")

    var known = sys.utc_time(Int64(1_700_000_000))
    check_int(h, known.year, Int64(2023), "known year")
    check_int(h, known.month, Int64(11), "known month")
    check_int(h, known.day, Int64(14), "known day")
    check_int(h, known.hour, Int64(22), "known hour")
    check_int(h, known.minute, Int64(13), "known minute")
    check_int(h, known.second, Int64(20), "known second")
    check_int(h, known.day_of_year, Int64(318), "known day of year")

    var leap = sys.utc_time(Int64(1_709_164_800))  # 2024-02-29T00:00:00Z
    check_int(h, leap.year, Int64(2024), "leap year")
    check_int(h, leap.month, Int64(2), "leap month")
    check_int(h, leap.day, Int64(29), "leap day")

    check_eq(h, sys.epoch_to_iso(Int64(0)), "19700101T000000", "iso epoch")
    check_eq(
        h, sys.epoch_to_iso(Int64(1_700_000_000)), "20231114T221320", "iso known moment"
    )
    check_eq(
        h,
        sys.epoch_to_iso(Int64(1_704_067_199)),
        "20231231T235959",
        "iso pads single digits",
    )
    check_eq(
        h,
        sys.epoch_to_iso(Int64(1_709_164_800)),
        "20240229T000000",
        "iso handles a leap day",
    )
    check_int(
        h,
        Int64(sys.local_epoch_to_iso(Int64(1_700_000_000)).byte_length()),
        Int64(15),
        "local iso has the same shape",
    )

    # Local time has to stay coherent whatever the timezone, so check the
    # invariants plus the offset glibc reports.
    var here = sys.local_time(Int64(1_700_000_000))
    check(h, here.month >= Int64(1) and here.month <= Int64(12), "month in range")
    check(h, here.day >= Int64(1) and here.day <= Int64(31), "day in range")
    check(h, here.hour >= Int64(0) and here.hour <= Int64(23), "hour in range")
    check(h, here.minute >= Int64(0) and here.minute <= Int64(59), "minute in range")
    check(h, here.second >= Int64(0) and here.second <= Int64(60), "second in range")
    check(h, here.weekday >= Int64(0) and here.weekday <= Int64(6), "weekday in range")
    check(h, here.day_of_year >= Int64(1) and here.day_of_year <= Int64(366),
        "day of year in range")
    check(h, here.utc_offset >= Int64(-50400) and here.utc_offset <= Int64(50400),
        "utc offset in range")
    check_int(
        h, here.utc_offset % Int64(900), Int64(0), "utc offset lands on a quarter hour"
    )

    # A day later must be exactly one day further on, modulo the year change.
    var day_after = sys.local_time(Int64(1_700_000_000 + 86400))
    var same_year = here.year == day_after.year
    if same_year:
        check_int(h, day_after.day_of_year, here.day_of_year + Int64(1), "day rolls over")

    # ---- picking a day -------------------------------------------------

    # A picked day is a calendar day, so the round trip has to land back on
    # that same day whatever the timezone is, including across a year change.
    for offset in range(Int64(0), Int64(4), Int64(1)):
        var moment = Int64(1_700_000_000) + offset * Int64(86_400_000) + Int64(1_234)
        var civil = sys.local_time(moment)
        var midnight = sys.local_midnight(civil.year, civil.month, civil.day)
        var back = sys.local_time(midnight)
        check_int(h, back.year, civil.year, "picked day keeps its year")
        check_int(h, back.month, civil.month, "picked day keeps its month")
        check_int(h, back.day, civil.day, "picked day keeps its day")
        check_int(h, back.hour, Int64(0), "picked day starts at midnight")
        check(h, midnight <= moment, "midnight is not after the moment in it")
        check(
            h,
            moment - midnight < Int64(86_400),
            "a moment sits inside its own day",
        )

    # The leap day is a day like any other to pick.
    var leap_day = sys.local_midnight(Int64(2024), Int64(2), Int64(29))
    var leap_back = sys.local_time(leap_day)
    check_int(h, leap_back.month, Int64(2), "leap day keeps its month")
    check_int(h, leap_back.day, Int64(29), "leap day keeps its day")
    check(
        h,
        leap_day == sys.local_midnight(Int64(2024), Int64(2), Int64(28)) + Int64(86_400),
        "a day after a leap day is one day later",
    )

    # Days come back out as a plain date, with dashes and padded numbers.
    check_eq(
        h, sys.local_date(sys.local_midnight(Int64(2026), Int64(9), Int64(27))),
        "2026-09-27",
        "a picked day reads back as a date",
    )
    check_eq(
        h,
        sys.local_date(sys.local_midnight(Int64(2026), Int64(1), Int64(5))),
        "2026-01-05",
        "single digit months and days are padded",
    )
    check_eq(
        h,
        sys.local_date(sys.local_midnight(Int64(1999), Int64(12), Int64(31))),
        "1999-12-31",
        "a date before 2000 keeps its year",
    )
    check_int(
        h, Int64(sys.local_date(leap_day).byte_length()), Int64(10), "date is ten characters"
    )

    # The day a moment falls on, counted on the calendar rather than on the
    # clock, which is what "yesterday" has to mean when the two moments are
    # only hours apart.
    var now = sys.now_epoch()
    var midnight = sys.local_midnight(Int64(2026), Int64(9), Int64(27))
    check_int(
        h,
        sys.local_day_number(midnight + Int64(23 * 3600 + 3599)),
        sys.local_day_number(midnight),
        "the whole day shares one number",
    )
    check_int(
        h,
        sys.local_day_number(midnight + Int64(86_400)),
        sys.local_day_number(midnight) + Int64(1),
        "a day later is one number later",
    )
    check_int(
        h,
        sys.local_day_number(midnight + Int64(86_399)),
        sys.local_day_number(midnight),
        "a moment before the next midnight is still the same day",
    )
    check_int(
        h,
        sys.local_day_number(midnight - Int64(60 * 60)),
        sys.local_day_number(midnight) - Int64(1),
        "an hour before midnight is the day before",
    )
    check_int(
        h,
        sys.local_day_number(now) - sys.local_day_number(midnight),
        Int64((now - midnight) // Int64(86_400)) - Int64((now % Int64(86_400)) == Int64(0)),
        "the day number is within a day of the elapsed count",
    )

    # ---- environment ---------------------------------------------------

    check(h, sys.get_env("PATH").byte_length() > 0, "PATH is readable")
    check_eq(h, sys.get_env("SMOKENOT_NOT_SET"), "", "missing var is empty")
    check_eq(h, sys.get_env("SMOKENOT_NOT_SET"), "", "missing var stays empty")

    var home = sys.data_home()
    check(h, home.byte_length() > 0, "data home is set")
    check_eq(h, sys.state_path(), home + "/smokenot/state.json", "state path layout")
    check_eq(
        h,
        sys.state_path(),
        sys.data_home() + "/smokenot/state.json",
        "state path is stable across calls",
    )

    # ---- files ---------------------------------------------------------

    # A scratch path, never the real state file: the suite has no business
    # writing where the app keeps the user's data.
    var path = "/tmp/opencode/smokenot-sys/files/state.txt"
    sys.write_file(path, "{\"cigs\": 20}\n")
    check_eq(h, sys.read_file(path), "{\"cigs\": 20}\n", "write then read back")
    check(h, path != sys.state_path(), "the suite never writes the real state file")

    sys.write_file(path, "")
    check_eq(h, sys.read_file(path), "", "empty file reads back empty")

    sys.write_file(path, "a")
    sys.write_file(path, "ab")
    check_eq(h, sys.read_file(path), "ab", "rewrite truncates")

    sys.write_file(path, "line\nwith \"quotes\" and café\n")
    check_eq(
        h,
        sys.read_file(path),
        "line\nwith \"quotes\" and café\n",
        "utf8 survives a round trip",
    )

    sys.write_file(path, "x" * 4096)
    check_int(h, Int64(sys.read_file(path).byte_length()), Int64(4096), "larger file")

    check_eq(h, sys.read_file("/tmp/opencode/smokenot-missing/state.json"), "",
        "missing file reads empty")
    check_eq(h, sys.read_file("/tmp/opencode/smokenot-missing/"), "",
        "unreadable path does not crash")
    check_eq(h, sys.read_file(""), "", "empty path does not crash")

    # Writing into a directory that does not exist creates it.
    var nested = "/tmp/opencode/smokenot-nested/deeper/state.json"
    sys.write_file(nested, "nested\n")
    check_eq(h, sys.read_file(nested), "nested\n", "write creates parent directory")
    sys.write_file(nested, "again\n")
    check_eq(h, sys.read_file(nested), "again\n", "second write to same path")
