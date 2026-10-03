"""System access: wall clock, local time, environment and file IO.

File IO, environment lookups and directory creation go through `std.io` and
`std.os` rather than raw libc. That matters for more than tidiness: the
stdlib already declares `fclose` for its own `FileHandle`, so a second
declaration of that symbol with a different signature fails to compile. The
clock stays on libc because the stdlib exposes monotonic time only, and the
app needs a wall clock to compare against the user's quit date.
"""

from std.ffi import c_char, c_int, c_long, external_call
from std.io import FileHandle
from std.os import getenv as _getenv
from std.os import mkdir as _mkdir
from std.os import remove as _remove
from lib.text import format_int


comptime CStrPtr = Pointer[c_char, MutUntrackedOrigin]
comptime SLASH: Byte = Byte(47)


# Matches glibc's `struct tm`, including the two glibc extensions.
@fieldwise_init
struct CTimeStruct(RegisterPassable):
    var tm_sec: c_int
    var tm_min: c_int
    var tm_hour: c_int
    var tm_mday: c_int
    var tm_mon: c_int
    var tm_year: c_int
    var tm_wday: c_int
    var tm_yday: c_int
    var tm_isdst: c_int
    var tm_gmtoff: c_long
    var tm_zone: Optional[CStrPtr]


struct CivilTime(ImplicitlyCopyable):
    var second: Int64
    var minute: Int64
    var hour: Int64
    var day: Int64
    var month: Int64
    var year: Int64
    var weekday: Int64
    var day_of_year: Int64
    var utc_offset: Int64

    def __init__(out self):
        self.second = Int64(0)
        self.minute = Int64(0)
        self.hour = Int64(0)
        self.day = Int64(0)
        self.month = Int64(0)
        self.year = Int64(0)
        self.weekday = Int64(0)
        self.day_of_year = Int64(0)
        self.utc_offset = Int64(0)


def now_epoch() -> Int64:
    """Seconds since the Unix epoch."""
    return Int64(
        external_call["time", c_long](Optional[Pointer[c_long, MutUntrackedOrigin]]())
    )


def _fill(epoch: Int64, mut target: CivilTime) -> Bool:
    """Shared `struct tm` unpacking for localtime_r and gmtime_r."""
    var when = epoch
    var storage = CTimeStruct(
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, Optional[CStrPtr]()
    )
    var found = external_call[
        "localtime_r", Optional[CStrPtr]
    ](Pointer(to=when), Pointer(to=storage))
    if not found:
        return False
    target.second = Int64(storage.tm_sec)
    target.minute = Int64(storage.tm_min)
    target.hour = Int64(storage.tm_hour)
    target.day = Int64(storage.tm_mday)
    # tm_mon is 0-based, tm_year counts from 1900.
    target.month = Int64(storage.tm_mon) + Int64(1)
    target.year = Int64(storage.tm_year) + Int64(1900)
    target.weekday = Int64(storage.tm_wday)
    target.day_of_year = Int64(storage.tm_yday) + Int64(1)
    target.utc_offset = Int64(storage.tm_gmtoff)
    return True


def local_time(epoch: Int64) -> CivilTime:
    """Break an epoch timestamp down in the user's local timezone."""
    var out = CivilTime()
    _ = _fill(epoch, out)
    return out


def local_midnight(year: Int64, month: Int64, day: Int64) -> Int64:
    """Local midnight of a calendar day, the other half of `local_time`.

    `mktime` reads the fields as a local time and writes back the offset it
    settled on, so daylight saving is libc's decision rather than the app's;
    `tm_isdst = -1` is what asks it to decide. The month is the one people
    count from one, not the zero based month `local_time` hands out.
    """
    var storage = CTimeStruct(
        0, 0, 0, c_int(day), c_int(month - 1), c_int(year - 1900), 0, 0, c_int(-1), 0,
        Optional[CStrPtr]()
    )
    return Int64(external_call["mktime", c_long](Pointer(to=storage)))


def utc_time(epoch: Int64) -> CivilTime:
    """Break an epoch timestamp down in UTC, independent of the timezone."""
    var out = CivilTime()
    var when = epoch
    var storage = CTimeStruct(
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, Optional[CStrPtr]()
    )
    var found = external_call[
        "gmtime_r", Optional[CStrPtr]
    ](Pointer(to=when), Pointer(to=storage))
    if not found:
        return out
    out.second = Int64(storage.tm_sec)
    out.minute = Int64(storage.tm_min)
    out.hour = Int64(storage.tm_hour)
    out.day = Int64(storage.tm_mday)
    out.month = Int64(storage.tm_mon) + Int64(1)
    out.year = Int64(storage.tm_year) + Int64(1900)
    out.weekday = Int64(storage.tm_wday)
    out.day_of_year = Int64(storage.tm_yday) + Int64(1)
    return out


def get_env(name: String) -> String:
    """Read an environment variable, or "" when unset."""
    return _getenv(String(name))


def data_home() -> String:
    """Base directory for user data.

    Inside a strict snap HOME is already $SNAP_USER_DATA, so the XDG lookup
    lands in the snap's own writable area without any special casing.
    """
    var xdg = get_env("XDG_DATA_HOME")
    if xdg.byte_length() > 0:
        return xdg
    var home = get_env("HOME")
    if home.byte_length() > 0:
        return home + "/.local/share"
    return String("/tmp")


def state_path() -> String:
    return data_home() + "/smokenot/state.json"


def ensure_parent_dir(path: String):
    """Create the directory holding `path` if it is missing.

    The stdlib's mkdir raises when the directory is already there, which is the
    common case on every run after the first, so the error is swallowed. The app
    only ever has one directory to create, so one level is enough.
    """
    var cut = -1
    var i = 0
    for b in path.bytes():
        if b == SLASH:
            cut = i
        i += 1
    if cut <= 0:
        return
    var parent = String(path[byte=0:cut])
    try:
        _mkdir(parent)
    except:
        return


def read_file(path: String) -> String:
    """Read a whole text file, returning "" when it cannot be read."""
    try:
        var handle = open(path, "r")
        var text = handle.read()
        handle.close()
        return text^
    except:
        return String("")


def write_file(path: String, contents: String):
    """Write a text file, replacing any previous contents."""
    ensure_parent_dir(path)
    try:
        var handle = open(path, "w")
        handle.write_string(contents)
        handle.close()
    except:
        return


def remove_file(path: String) -> Bool:
    """Delete a file, saying whether it was there to delete."""
    try:
        _remove(path)
        return True
    except:
        return False


def epoch_to_iso(epoch: Int64) -> String:
    """Format an epoch as YYYY-MM-DDTHH:MM:SSZ in UTC."""
    return _iso(utc_time(epoch))


def local_epoch_to_iso(epoch: Int64) -> String:
    """Format an epoch in the local timezone, for display."""
    return _iso(local_time(epoch))


def local_day_number(epoch: Int64) -> Int64:
    """The local calendar day an epoch falls on, counted from year one.

    Two epochs on the same day always answer the same, and neighbouring days
    differ by exactly one, whatever the hour and whatever the offset: the clock
    is left out of it on purpose. A day off is a day off even when a
    daylight saving switch, or a saved date that was not written at midnight,
    puts the two moments hours apart.
    """
    var t = local_time(epoch)
    return _days_from_civil(t.year, t.month, t.day)


def _days_from_civil(year: Int64, month: Int64, day: Int64) -> Int64:
    """Days between 1970-01-01 and a proleptic Gregorian day, Howard Hinnant's
    `days_from_civil`, shifted so the epoch lands on zero."""
    var y = year
    var m = month
    if m <= Int64(2):
        y -= Int64(1)
        m += Int64(12)
    var era = (y if y >= Int64(0) else y - Int64(399)) // Int64(400)
    var yoe = y - era * Int64(400)
    var doy = (Int64(153) * (m - Int64(3)) + Int64(2)) // Int64(5) + day - Int64(1)
    var doe = yoe * Int64(365) + yoe // Int64(4) - yoe // Int64(100) + doy
    return era * Int64(146097) + doe - Int64(719468)


def local_date(epoch: Int64) -> String:
    """The local calendar day an epoch falls on, as YYYY-MM-DD.

    A picked day is a day in the user's own calendar, so it reads back through
    the local timezone and shows dashes, which is how a date is written down
    everywhere else.
    """
    var t = local_time(epoch)
    return format_int(t.year) + String("-") + _two(t.month) + String("-") + _two(t.day)


def _iso(t: CivilTime) -> String:
    var out = format_int(t.year)
    out += _two(t.month)
    out += _two(t.day)
    out += String("T")
    out += _two(t.hour)
    out += _two(t.minute)
    out += _two(t.second)
    return out


def _two(value: Int64) -> String:
    var text = format_int(value)
    if text.byte_length() >= 2:
        return text
    return String("0") + text
