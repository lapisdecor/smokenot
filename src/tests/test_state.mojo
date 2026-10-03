from i18n.strings import LANG_EN, LANG_PT
from lib import sys
from model.state import (
    DEFAULT_CIGS_PER_DAY,
    KIND_CRAVING,
    KIND_SLIP,
    MAX_JOURNAL_ENTRIES,
    SCHEMA_VERSION,
    JournalEntry,
    defaults,
    load,
    save,
    to_json,
)
from tests.harness import Harness, begin_suite, check, check_eq, check_float, check_int

comptime TEST_PATH = "/tmp/opencode/smokenot-selftest/state.json"
comptime NOW = Int64(1700000000)


def _unlink() raises:
    # There is no remove yet, so an empty write stands in for a missing file.
    sys.write_file(TEST_PATH, String(""))


def _midnight_of(epoch: Int64) -> Int64:
    """Local midnight of the day a timestamp falls on.

    Stepping a whole day at a time and asking which day the answer lands on
    keeps a daylight saving switch from moving the date, so "tomorrow" in a test
    is the day after today whatever the hour.
    """
    var target = sys.local_day_number(epoch)
    var step = epoch
    while sys.local_day_number(step) > target:
        step -= Int64(86_400)
    while sys.local_day_number(step) < target:
        step += Int64(86_400)
    var civil = sys.local_time(step)
    return sys.local_midnight(civil.year, civil.month, civil.day)


def run(mut h: Harness) raises:
    begin_suite(h, "model.state")

    # ---- defaults -------------------------------------------------------

    var fresh = defaults()
    check_int(h, Int64(fresh.version), Int64(SCHEMA_VERSION), "default version")
    check(h, not fresh.loaded_from_disk, "defaults are not from disk")
    check(h, not fresh.is_configured(), "defaults are unconfigured")
    check_int(h, Int64(fresh.entry_count()), Int64(0), "defaults have no entries")
    check_int(h, Int64(fresh.slip_count()), Int64(0), "defaults have no slips")
    check_int(h, fresh.newest_entry_epoch(), Int64(0), "defaults have no newest entry")
    check_int(h, fresh.profile.cigs_per_day, Int64(DEFAULT_CIGS_PER_DAY), "suggested default")
    check_int(h, Int64(fresh.profile.language), Int64(LANG_PT), "default language is portuguese")
    check(h, not fresh.profile.is_planned(NOW), "an unset quit date is not planned")
    check(h, not fresh.profile.is_quit_day(NOW), "an unset quit date is not today")

    # ---- start_fresh ----------------------------------------------------

    var reset = defaults()
    reset.profile.mark_configured()
    reset.profile.cigs_per_day = Int64(40)
    reset.profile.quit_epoch = Int64(500)
    reset.add_entry(NOW, KIND_SLIP, "one")
    check(h, reset.is_configured(), "configured before reset")
    reset.start_fresh(NOW, Int64(NOW + 86400))
    check(h, not reset.is_configured(), "reset is unconfigured again")
    check_int(h, Int64(reset.entry_count()), Int64(0), "reset clears the journal")
    check_int(h, reset.profile.created_epoch, NOW, "reset stamps the creation time")
    check_int(h, reset.profile.quit_epoch, Int64(NOW + 86400), "reset keeps the planned date")
    check(h, reset.profile.is_planned(NOW), "a future date is planned")

    # ---- the quit day ---------------------------------------------------
    #
    # Three moments matter: a day still to come is a plan, the day itself waits
    # for the user to press the button, and a day that is today starts counting
    # the moment the settings are saved. The dates here are the real thing,
    # counted on the calendar, so the tests do not care what hour they run at.

    var today_mid = _midnight_of(NOW)
    var tomorrow_mid = _midnight_of(NOW + Int64(86_400))

    var today_pick = defaults()
    today_pick.profile.set_quit_day(today_mid, NOW)
    check_int(
        h, today_pick.profile.quit_epoch, NOW, "a day that is today starts now, not at midnight"
    )
    check(h, today_pick.profile.quit_started, "a day that is today is already counting")
    check(h, not today_pick.profile.is_planned(NOW), "a started count is not a plan")
    check(h, not today_pick.profile.is_quit_day(NOW), "a started count is not waiting for a press")

    var later_today = defaults()
    # Ten minutes into the same day: still today, and still counted from when
    # the settings were saved.
    later_today.profile.set_quit_day(today_mid, NOW + Int64(600))
    check_int(h, later_today.profile.quit_epoch, Int64(NOW + 600), "the hour does not move the start")

    var future_pick = defaults()
    future_pick.profile.set_quit_day(tomorrow_mid, NOW)
    check_int(h, future_pick.profile.quit_epoch, tomorrow_mid, "a future day is kept at its midnight")
    check(h, not future_pick.profile.quit_started, "a future day has not started")
    check(h, future_pick.profile.is_planned(NOW), "a future day is a plan")
    check(h, not future_pick.profile.is_quit_day(NOW), "a future day is not today")
    # On the day itself, before the press, the count is waiting.
    check(h, future_pick.profile.is_quit_day(tomorrow_mid), "the chosen day is the day itself")
    check(h, not future_pick.profile.is_quit_day(tomorrow_mid + Int64(86_400)), "the day is over by the next day")
    check(h, not future_pick.profile.is_planned(tomorrow_mid), "on the day there is nothing to wait for")

    # The button: the day arrives, the count starts from the press.
    var pressed = defaults()
    pressed.profile.set_quit_day(tomorrow_mid, NOW)
    var press_at = tomorrow_mid + Int64(9 * 3600)
    pressed.profile.start_counting(press_at)
    check_int(h, pressed.profile.quit_epoch, press_at, "the press is the moment that is kept")
    check(h, pressed.profile.quit_started, "the press starts the count")
    check(h, not pressed.profile.is_quit_day(press_at), "a started count waits for nothing")
    check(h, not pressed.profile.is_planned(press_at), "a started count is not a plan")
    check_int(h, pressed.profile.gains(press_at + Int64(3600)).days, Int64(0), "the first hour is not a day")
    check_int(
        h,
        pressed.profile.gains(press_at + Int64(86_400)).days,
        Int64(1),
        "a whole day after the press counts as one day",
    )

    var past_pick = defaults()
    past_pick.profile.set_quit_day(today_mid, NOW + Int64(2 * 86_400))
    check_int(h, past_pick.profile.quit_epoch, today_mid, "a day that has gone keeps its midnight")
    check(h, past_pick.profile.quit_started, "a day that has gone is counting")

    var no_day = defaults()
    no_day.profile.quit_started = True
    no_day.profile.quit_epoch = Int64(0)
    no_day.profile.set_quit_day(Int64(0), NOW)
    check_int(h, no_day.profile.quit_epoch, Int64(0), "no day is not a day to set")
    check(h, not no_day.profile.is_planned(NOW), "no day is not a plan")

    # ---- round trip of the flag ----------------------------------------

    var planned = defaults()
    planned.profile.mark_configured()
    planned.profile.set_quit_day(tomorrow_mid, NOW)
    _unlink()
    save(TEST_PATH, planned)
    var planned_back = load(TEST_PATH)
    check(h, not planned_back.profile.quit_started, "a plan is still a plan after the round trip")
    check(h, planned_back.profile.is_planned(NOW), "the plan survives the round trip")
    check_int(h, planned_back.profile.quit_epoch, tomorrow_mid, "the planned day survives")

    # A file written before the flag existed carries only a date, and a date
    # that has already gone was a count that was under way.
    sys.write_file(
        TEST_PATH,
        String('{"version":1,"profile":{"cigs_per_day":20,"pack_size":20,')
        + String('"pack_price":7.0,"quit_epoch":')
        + String(NOW - Int64(86_400))
        + String(',"created_epoch":1,"language":"pt_PT","configured":true},"journal":[]}\n'),
    )
    var legacy_no_flag = load(TEST_PATH)
    check(h, legacy_no_flag.loaded_from_disk, "a file without the flag still loads")
    check(h, legacy_no_flag.profile.quit_started, "a past date counts as already running")
    check(h, not legacy_no_flag.profile.is_planned(NOW), "a past date is not a plan")

    # The other way round: an old file whose date is still to come was a plan,
    # and it stays one instead of jumping straight to counting. The date is
    # measured against the real clock here, not against NOW, because that is
    # what the file migration does: it is the one place a stored timestamp is
    # read without a caller to hand it a moment.
    sys.write_file(
        TEST_PATH,
        String('{"version":1,"profile":{"cigs_per_day":20,"pack_size":20,')
        + String('"pack_price":7.0,"quit_epoch":')
        + String(sys.now_epoch() + Int64(86_400))
        + String(',"created_epoch":1,"language":"pt_PT","configured":true},"journal":[]}\n'),
    )
    var legacy_plan = load(TEST_PATH)
    check(h, not legacy_plan.profile.quit_started, "a future date in an old file is still a plan")
    check(
        h,
        legacy_plan.profile.is_planned(sys.now_epoch()),
        "the plan in an old file survives the load",
    )

    # ---- entries --------------------------------------------------------

    var journal = defaults()
    journal.add_entry(NOW, KIND_CRAVING, "after lunch")
    journal.add_entry(NOW + 1, KIND_SLIP, "")
    journal.add_entry(NOW + 2, KIND_CRAVING, "evening")
    check_int(h, Int64(journal.entry_count()), Int64(3), "three entries")
    check_int(h, Int64(journal.slip_count()), Int64(1), "one slip")
    check_int(h, journal.newest_entry_epoch(), Int64(NOW + 2), "newest entry reported")
    check_eq(h, journal.entries()[0].note, "evening", "newest entry first")
    check_eq(h, journal.entries()[2].note, "after lunch", "oldest entry last")
    check(h, journal.entries()[1].is_slip(), "middle entry is the slip")
    check(h, not journal.entries()[0].is_slip(), "newest entry is a craving")

    journal.add_entry(NOW + 3, Int(9), "bad kind")
    journal.add_entry(NOW + 3, Int(-1), "negative kind")
    check_int(h, Int64(journal.entry_count()), Int64(3), "unknown kinds are ignored")
    check_eq(h, journal.entries()[0].note, "evening", "a rejected entry is not stored")

    var cravings = journal.entries_of_kind(KIND_CRAVING)
    check_int(h, Int64(len(cravings)), Int64(2), "two cravings")
    var slips = journal.entries_of_kind(KIND_SLIP)
    check_int(h, Int64(len(slips)), Int64(1), "one slip of a kind")
    check_eq(h, slips[0].note, "", "an empty note stays empty")

    # ---- notes that need escaping ---------------------------------------

    # A note is written into the journal blob on one line, so anything that
    # could break that line apart has to survive the round trip.
    var awkward = defaults()
    awkward.add_entry(NOW - 5, KIND_CRAVING, "")
    awkward.add_entry(NOW - 4, KIND_CRAVING, "acentuação ok")
    awkward.add_entry(NOW - 3, KIND_CRAVING, "12 34 five")
    awkward.add_entry(NOW - 2, KIND_CRAVING, "  padded  ")
    awkward.add_entry(NOW - 1, KIND_SLIP, "back \\ slash")
    awkward.add_entry(NOW, KIND_CRAVING, "line one\nline two")
    var notes = awkward.entries()
    check_int(h, Int64(len(notes)), Int64(6), "every awkward note is kept")
    check_eq(h, notes[0].note, "line one\nline two", "a newline survives")
    check_eq(h, notes[1].note, "back \\ slash", "a backslash survives")
    check_eq(h, notes[2].note, "  padded  ", "padding spaces survive")
    check_eq(h, notes[3].note, "12 34 five", "spaces inside a note survive")
    check_eq(h, notes[4].note, "acentuação ok", "a non-ascii note survives")
    check_eq(h, notes[5].note, "", "an awkward empty note stays empty")
    check_int(h, Int64(awkward.slip_count()), Int64(1), "escaping does not confuse the kind")

    # ---- cap ------------------------------------------------------------

    var capped = defaults()
    var i = 0
    while i < MAX_JOURNAL_ENTRIES + 25:
        capped.add_entry(NOW + Int64(i), KIND_CRAVING, "n")
        i += 1
    check_int(h, Int64(capped.entry_count()), Int64(MAX_JOURNAL_ENTRIES), "journal is capped")
    check_int(
        h, capped.entries()[0].epoch, NOW + Int64(MAX_JOURNAL_ENTRIES + 24), "the newest entry is first"
    )
    check_int(
        h,
        capped.entries()[MAX_JOURNAL_ENTRIES - 1].epoch,
        NOW + Int64(25),
        "the cap dropped the oldest entries",
    )

    # ---- clamp ----------------------------------------------------------

    var wild = defaults()
    wild.profile.cigs_per_day = Int64(-5)
    wild.profile.pack_size = Int64(0)
    wild.profile.pack_price = Float64(-1.0)
    wild.profile.quit_epoch = Int64(-100)
    wild.profile.created_epoch = Int64(-1)
    wild.profile.language = Int(7)
    wild.profile.clamp()
    check_int(h, wild.profile.cigs_per_day, Int64(0), "negative habit clamps to zero")
    check_int(h, wild.profile.pack_size, Int64(1), "zero pack size becomes one")
    check_float(h, wild.profile.pack_price, Float64(0.0), "negative price clamps to zero")
    check_int(h, wild.profile.quit_epoch, Int64(0), "negative date clamps to zero")
    check_int(h, Int64(wild.profile.language), Int64(LANG_PT), "unknown language falls back")
    check(h, not wild.is_configured(), "a clamped wild profile is not usable")

    var huge = defaults()
    huge.profile.cigs_per_day = Int64(100000)
    huge.profile.pack_size = Int64(100000)
    huge.profile.pack_price = Float64(1e12)
    huge.profile.clamp()
    check(h, huge.profile.cigs_per_day > Int64(0), "large habit stays positive")
    check(h, huge.profile.pack_size > Int64(0), "large pack stays positive")
    check(h, huge.profile.pack_price < Float64(1e12), "large price is capped")

    # ---- round trip -----------------------------------------------------

    var state = defaults()
    state.profile.mark_configured()
    state.profile.cigs_per_day = Int64(15)
    state.profile.pack_size = Int64(25)
    state.profile.pack_price = Float64(8.35)
    state.profile.quit_epoch = Int64(NOW - 3600)
    state.profile.created_epoch = NOW
    state.profile.language = LANG_EN
    state.add_entry(NOW - 100, KIND_CRAVING, "note with \"quotes\" and \\ backslash")
    state.add_entry(NOW - 50, KIND_SLIP, "recaída")

    _unlink()
    save(TEST_PATH, state)
    var back = load(TEST_PATH)
    check(h, back.loaded_from_disk, "loaded from disk")
    check(h, back.is_configured(), "configured survives the round trip")
    check_int(h, Int64(back.version), Int64(SCHEMA_VERSION), "version survives")
    check_int(h, back.profile.cigs_per_day, Int64(15), "habit survives")
    check_int(h, back.profile.pack_size, Int64(25), "pack size survives")
    check_float(h, back.profile.pack_price, Float64(8.35), "fractional price survives")
    check_float(h, back.profile.cost_per_cigarette(), Float64(8.35) / Float64(25), "cost per cig")
    check_int(h, back.profile.quit_epoch, Int64(NOW - 3600), "quit date survives")
    check_int(h, back.profile.created_epoch, NOW, "created time survives")
    check_int(h, Int64(back.profile.language), Int64(LANG_EN), "language survives")
    check_int(h, Int64(back.entry_count()), Int64(2), "entries survive")
    check_int(h, Int64(back.slip_count()), Int64(1), "slip survives")
    check_eq(h, back.entries()[0].note, "recaída", "newest entry stays first")
    check_eq(h, back.entries()[1].note, "note with \"quotes\" and \\ backslash", "note survives")

    # A whole price must not be lost, and a zero price must not become the
    # suggestion.
    var whole = defaults()
    whole.profile.mark_configured()
    whole.profile.pack_price = Float64(9.0)
    save(TEST_PATH, whole)
    check_float(h, load(TEST_PATH).profile.pack_price, Float64(9.0), "whole price survives")
    var free = defaults()
    free.profile.mark_configured()
    free.profile.pack_price = Float64(0.0)
    save(TEST_PATH, free)
    check_float(h, load(TEST_PATH).profile.pack_price, Float64(0.0), "zero price survives")

    # Portuguese is the written default.
    var pt = defaults()
    pt.profile.mark_configured()
    save(TEST_PATH, pt)
    check_int(h, Int64(load(TEST_PATH).profile.language), Int64(LANG_PT), "pt survives")

    # ---- damage ---------------------------------------------------------

    _unlink()
    var missing = load(TEST_PATH)
    check(h, not missing.loaded_from_disk, "a missing file is not from disk")
    check(h, not missing.is_configured(), "a missing file asks for onboarding")

    sys.write_file(TEST_PATH, String("{ this is not json"))
    var broken = load(TEST_PATH)
    check(h, not broken.loaded_from_disk, "a broken file is not from disk")
    check(h, not broken.is_configured(), "a broken file asks for onboarding")

    sys.write_file(TEST_PATH, String("[1, 2, 3]"))
    var array = load(TEST_PATH)
    check(h, not array.loaded_from_disk, "an array is not a state file")
    check_int(h, Int64(array.entry_count()), Int64(0), "an array loads no entries")

    sys.write_file(TEST_PATH, String("{}"))
    var empty_object = load(TEST_PATH)
    check(h, not empty_object.is_configured(), "an empty object asks for onboarding")
    check_int(h, empty_object.profile.cigs_per_day, Int64(DEFAULT_CIGS_PER_DAY), "suggestion kept")

    # Numbers out of range in the file are clamped, not refused.
    sys.write_file(
        TEST_PATH,
        String(
            String('{"version":1,"profile":{"cigs_per_day":-4,"pack_size":0,')
            + String('"pack_price":-2.0,"quit_epoch":-9,"created_epoch":-9,')
            + String('"language":"klingon","configured":true},"journal":[]}')
        ),
    )
    var wild_load = load(TEST_PATH)
    check(h, not wild_load.is_configured(), "a flag cannot survive a zeroed habit")
    check_int(h, wild_load.profile.cigs_per_day, Int64(0), "file habit clamped on load")
    check_int(h, wild_load.profile.pack_size, Int64(1), "file pack size clamped on load")
    check_float(h, wild_load.profile.pack_price, Float64(0.0), "file price clamped on load")
    check_int(h, Int64(wild_load.profile.language), Int64(LANG_PT), "file language falls back")

    sys.write_file(
        TEST_PATH,
        String(
            String('{"version":1,"profile":{"cigs_per_day":12,"pack_size":20,')
            + String('"pack_price":6.5,"quit_epoch":1,"created_epoch":1,')
            + String('"language":"pt_PT","configured":true},"journal":[]}')
        ),
    )
    var flagged = load(TEST_PATH)
    check(h, flagged.is_configured(), "a configured file opens the dashboard")
    check_float(h, flagged.profile.pack_price, Float64(6.5), "flagged file price read")

    # A file from before the flag is still usable.
    sys.write_file(
        TEST_PATH,
        String(
            String('{"version":1,"profile":{"cigs_per_day":10,"pack_size":20,')
            + String('"pack_price":7.0,"quit_epoch":1,"created_epoch":1,')
            + String('"language":"en"},"journal":[]}')
        ),
    )
    var legacy = load(TEST_PATH)
    check(h, legacy.is_configured(), "an old file is still configured")
    check_int(h, Int64(legacy.profile.language), Int64(LANG_EN), "old file language read")
    check_float(h, legacy.profile.pack_price, Float64(7.0), "old file price read")

    # Junk in the journal is skipped rather than fatal.
    sys.write_file(
        TEST_PATH,
        String(
            String('{"version":9,"profile":{"cigs_per_day":5,"pack_size":5,')
            + String('"pack_price":1.0,"quit_epoch":1,"created_epoch":1,')
            + String('"language":"pt_PT","configured":true},"journal":')
            + String('[3,"nope",{"epoch":77,"kind":"slip","note":"kept"},')
            + String('{"kind":"weird"},{"epoch":78}],"extra":true}')
        ),
    )
    var junk = load(TEST_PATH)
    check_int(h, Int64(junk.version), Int64(9), "a newer version is read as written")
    check_int(h, Int64(junk.entry_count()), Int64(3), "only object entries are read")
    check_int(h, junk.entries()[0].epoch, Int64(77), "entries keep the order of the file")
    check_eq(h, junk.entries()[0].note, "kept", "good entry note read")
    check_int(h, junk.entries()[1].epoch, Int64(0), "entry without an epoch reads as zero")
    check(h, not junk.entries()[1].is_slip(), "an unknown kind is not a slip")
    check_int(h, junk.entries()[2].epoch, Int64(78), "last entry read")
    check(h, not junk.profile.is_planned(NOW), "a past date is not planned")

    # ---- document shape -------------------------------------------------

    var doc = to_json(state)
    check_int(h, Int64(doc.int_at(doc.root, 0)), Int64(SCHEMA_VERSION), "document starts with the version")
    var profile_node = doc.get("profile")
    check(h, profile_node >= 0, "document has a profile")
    check_float(
        h, doc.get_member_float(profile_node, "pack_price", Float64(0.0)), Float64(8.35), "price as a number"
    )
    check_float(
        h, doc.get_member_float(profile_node, "cigs_per_day", Float64(0.0)), Float64(15), "int reads as float"
    )
    check(h, doc.has_member(profile_node, "configured"), "document records configured")
    check(h, not doc.has_member(profile_node, "nope"), "absent member reported")
    check_float(h, doc.get_member_float(profile_node, "nope", Float64(-1.0)), Float64(-1.0), "absent float fallback")
    check(h, doc.get_member_float(profile_node, "language", Float64(0.0)) == Float64(0.0), "wrong kind falls back")
    var journal_node = doc.get("journal")
    check(h, doc.count(journal_node) == 2, "document has both entries")
    _ = JournalEntry(NOW, KIND_CRAVING, String("x"))
    _unlink()
