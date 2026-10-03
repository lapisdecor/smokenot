# Copyright (C) 2026 Luís Louro
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Licensed under the GNU General Public License, version 3 or later. The full
# text is in LICENSE.

from model.stats import (
    SECONDS_PER_DAY,
    SECONDS_PER_HOUR,
    SECONDS_PER_MINUTE,
    cost_per_cigarette,
    daily_cost,
    elapsed_since,
    hours_smoke_free,
    money_per_day,
    seconds_text,
    compute,
)
from tests.harness import Harness, begin_suite, check, check_eq, check_float, check_int


def run(mut h: Harness):
    begin_suite(h, "model.stats")

    check_int(h, Int64(SECONDS_PER_MINUTE), Int64(60), "seconds per minute")
    check_int(h, Int64(SECONDS_PER_HOUR), Int64(3600), "seconds per hour")
    check_int(h, Int64(SECONDS_PER_DAY), Int64(86400), "seconds per day")

    # ---- elapsed -------------------------------------------------------

    check_int(h, elapsed_since(Int64(100), Int64(160)), Int64(60), "elapsed")
    check_int(h, elapsed_since(Int64(100), Int64(100)), Int64(0), "elapsed at the start")
    check_int(h, elapsed_since(Int64(100), Int64(0)), Int64(0), "future quit is zero")
    check_int(h, elapsed_since(Int64(0), Int64(-500)), Int64(0), "never negative")

    # ---- cost ----------------------------------------------------------

    check_float(h, cost_per_cigarette(Float64(7.5), Int64(20)), Float64(0.375), "per cigarette")
    check_float(h, cost_per_cigarette(Float64(8.0), Int64(10)), Float64(0.8), "per cigarette two")
    check_float(h, cost_per_cigarette(Float64(7.5), Int64(0)), Float64(0.0), "zero pack size")
    check_float(h, cost_per_cigarette(Float64(7.5), Int64(-5)), Float64(0.0), "negative pack size")
    check_float(h, cost_per_cigarette(Float64(-1.0), Int64(20)), Float64(0.0), "negative price")
    check_float(h, daily_cost(Int64(20), Float64(7.5), Int64(20)), Float64(7.5), "daily cost")
    check_float(h, daily_cost(Int64(0), Float64(7.5), Int64(20)), Float64(0.0), "no cigarettes")
    check_float(h, money_per_day(Int64(20), Float64(7.5), Int64(20)), Float64(7.5), "money per day")

    # ---- compute -------------------------------------------------------

    # One day of a 20 a day habit at 7.50 per 20 pack.
    var day = compute(Int64(20), Float64(7.5), Int64(20), Int64(0), Int64(86400))
    check_float(h, day.money, Float64(7.5), "one day of money")
    check_float(h, day.cigarettes, Float64(20.0), "one day of cigarettes")
    check_float(h, day.life_minutes, Float64(220.0), "one day of life")
    check_int(h, day.days, Int64(1), "one day count")
    check_int(h, day.elapsed_seconds, Int64(86400), "one day elapsed")
    check_int(h, hours_smoke_free(day), Int64(24), "one day hours")

    # Half a day is half of everything.
    var half = compute(Int64(20), Float64(7.5), Int64(20), Int64(0), Int64(43200))
    check_float(h, half.money, Float64(3.75), "half a day of money")
    check_float(h, half.cigarettes, Float64(10.0), "half a day of cigarettes")
    check_int(h, half.days, Int64(0), "half a day count")

    # A day before the quit date earns nothing.
    var before = compute(Int64(20), Float64(7.5), Int64(20), Int64(86400), Int64(0))
    check_float(h, before.money, Float64(0.0), "before quitting earns nothing")
    check_float(h, before.cigarettes, Float64(0.0), "before quitting no cigarettes")
    check_int(h, before.days, Int64(0), "before quitting no days")

    # A year scales linearly.
    var year = compute(Int64(20), Float64(7.5), Int64(20), Int64(0), Int64(86400 * 365))
    check_float(h, year.money, Float64(2737.5), "a year of money")
    check_float(h, year.cigarettes, Float64(7300.0), "a year of cigarettes")
    check_float(h, year.life_minutes, Float64(80300.0), "a year of life")
    check_int(h, year.days, Int64(365), "a year of days")

    # A bigger pack divides the cost further.
    var cheap = compute(Int64(40), Float64(20.0), Int64(20), Int64(0), Int64(86400))
    check_float(h, cheap.money, Float64(40.0), "forty a day at 20 per pack")
    check_float(h, cheap.cigarettes, Float64(40.0), "forty cigarettes a day")

    # Degenerate profiles must not produce garbage.
    var empty = compute(Int64(0), Float64(0.0), Int64(0), Int64(0), Int64(86400))
    check_float(h, empty.money, Float64(0.0), "empty profile money")
    check_float(h, empty.cigarettes, Float64(0.0), "empty profile cigarettes")
    check_float(h, empty.life_minutes, Float64(0.0), "empty profile life")

    var no_pack = compute(Int64(20), Float64(7.5), Int64(0), Int64(0), Int64(86400))
    check_float(h, no_pack.money, Float64(0.0), "zero pack size money")
    check_float(h, no_pack.cigarettes, Float64(20.0), "zero pack size still counts cigarettes")

    # Truncation for display.
    var part = compute(Int64(20), Float64(7.5), Int64(20), Int64(0), Int64(1000))
    check_int(h, part.whole_cigarettes(), Int64(0), "under a cigarette truncates")
    check_int(h, part.whole_life_minutes(), Int64(2), "life minutes truncate")
    var part2 = compute(Int64(20), Float64(7.5), Int64(20), Int64(0), Int64(43200))
    check_int(h, part2.whole_life_minutes(), Int64(110), "half day life minutes")

    check_eq(h, seconds_text(day), "1d 0h 0m", "seconds text one day")
    check_eq(h, seconds_text(half), "0d 12h 0m", "seconds text half day")
    check_eq(
        h, seconds_text(compute(Int64(20), Float64(7.5), Int64(20), Int64(0), Int64(90061))),
        "1d 1h 1m",
        "seconds text with remainder",
    )
