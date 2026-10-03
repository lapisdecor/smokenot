"""The recovery timeline.

Each entry is a published figure for what the body has regained by that point
in a smoke-free run. The list is ordered, so counting how many have been
passed doubles as the progress indicator.
"""

from model.stats import SECONDS_PER_DAY, SECONDS_PER_HOUR, SECONDS_PER_MINUTE
from lib.text import format_int


comptime MINUTE: Int64 = SECONDS_PER_MINUTE
comptime HOUR: Int64 = SECONDS_PER_HOUR
comptime DAY: Int64 = SECONDS_PER_DAY
comptime WEEK: Int64 = SECONDS_PER_DAY * Int64(7)
comptime MONTH: Int64 = SECONDS_PER_DAY * Int64(30)
comptime YEAR: Int64 = SECONDS_PER_DAY * Int64(365)


struct Milestone(ImplicitlyCopyable):
    var seconds: Int64
    var key: String

    def __init__(out self, seconds: Int64, key: String):
        self.seconds = seconds
        self.key = key


def all() -> List[Milestone]:
    """Every milestone, soonest first."""
    var out = List[Milestone]()
    out.append(Milestone(MINUTE * Int64(20), "milestone_20min"))
    out.append(Milestone(HOUR * Int64(8), "milestone_8h"))
    out.append(Milestone(DAY, "milestone_24h"))
    out.append(Milestone(DAY * Int64(2), "milestone_48h"))
    out.append(Milestone(DAY * Int64(3), "milestone_72h"))
    out.append(Milestone(WEEK, "milestone_1w"))
    out.append(Milestone(WEEK * Int64(2), "milestone_2w"))
    out.append(Milestone(MONTH, "milestone_1m"))
    out.append(Milestone(MONTH * Int64(3), "milestone_3m"))
    out.append(Milestone(MONTH * Int64(9), "milestone_9m"))
    out.append(Milestone(YEAR, "milestone_1y"))
    out.append(Milestone(YEAR * Int64(5), "milestone_5y"))
    out.append(Milestone(YEAR * Int64(10), "milestone_10y"))
    out.append(Milestone(YEAR * Int64(15), "milestone_15y"))
    return out^


def count() -> Int:
    return len(all())


def reached_count(elapsed_seconds: Int64) -> Int:
    """How many milestones have been passed."""
    var n = 0
    for milestone in all():
        if elapsed_seconds >= milestone.seconds:
            n += 1
    return n


def is_reached(index: Int, elapsed_seconds: Int64) -> Bool:
    var list = all()
    if index < 0 or index >= len(list):
        return False
    return elapsed_seconds >= list[index].seconds


def next_index(elapsed_seconds: Int64) -> Int:
    """Index of the next milestone, or -1 when the list is complete."""
    var list = all()
    for i in range(len(list)):
        if elapsed_seconds < list[i].seconds:
            return i
    return -1


def progress(elapsed_seconds: Int64) -> Float64:
    """Fraction of the way to the next milestone, 0.0 to 1.0.

    The first milestone has nothing before it, so the run up to it starts at
    0.0. Completing the whole list reads as 1.0 rather than dividing by zero.
    """
    var list = all()
    var index = next_index(elapsed_seconds)
    if index < 0:
        return Float64(1.0)
    if index == 0:
        var target = list[0].seconds
        if target <= Int64(0) or elapsed_seconds >= target:
            return Float64(1.0)
        return Float64(elapsed_seconds) / Float64(target)
    var previous = list[index - 1].seconds
    var target = list[index].seconds
    var span = target - previous
    if span <= Int64(0):
        return Float64(1.0)
    var done = elapsed_seconds - previous
    if done < Int64(0):
        return Float64(0.0)
    return Float64(done) / Float64(span)


def next_seconds_remaining(elapsed_seconds: Int64) -> Int64:
    """Time left until the next milestone, or 0 once the list is done."""
    var list = all()
    var index = next_index(elapsed_seconds)
    if index < 0:
        return Int64(0)
    return list[index].seconds - elapsed_seconds


def summary_key(elapsed_seconds: Int64) -> String:
    """Translation key naming the next milestone, or "" once the list is done.

    The key is what the interface asks the translations for, so the milestone
    names live in one place instead of being spelled out twice.
    """
    var list = all()
    var index = next_index(elapsed_seconds)
    if index < 0:
        return String("")
    return list[index].key


def elapsed_label(seconds: Int64) -> String:
    """Compact duration of a milestone: '20 min', '8 h', '3 mo', '5 y'."""
    if seconds < HOUR:
        return format_int(seconds // MINUTE) + " min"
    if seconds < DAY:
        return format_int(seconds // HOUR) + " h"
    if seconds < MONTH:
        return format_int(seconds // DAY) + " d"
    if seconds < YEAR:
        return format_int(seconds // MONTH) + " mo"
    return format_int(seconds // YEAR) + " y"
