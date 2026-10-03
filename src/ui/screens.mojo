# Copyright (C) 2026 Luís Louro
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Licensed under the GNU General Public License, version 3 or later. The full
# text is in LICENSE.

"""Building the window and keeping its text up to date.

Nothing here is a callback. The screens are plain functions that create widgets
or rewrite labels, and `ui.handlers` is what GTK calls, which keeps the
dependency pointing one way: handlers know about screens, screens do not know
about handlers.
"""

from gtk import gtk
from i18n.strings import LANG_EN, LANG_PT, Translations
from lib import sys
from lib.text import format_fixed, format_int, parse_float, parse_int
from model import milestones
from model.state import (
    JournalEntry,
    save,
)
from model.stats import SECONDS_PER_DAY
from std.ffi import c_double, c_float, c_int, c_uint
from ui.host import Widget, is_null, model_of, ui_of

comptime STYLE_PRIORITY: c_uint = c_uint(600)
comptime TAU: c_double = c_double(6.28318)

comptime SOS_SECONDS: Int32 = Int32(300)
comptime BREATHE_IN: Int32 = Int32(4)
comptime BREATHE_HOLD: Int32 = Int32(2)
comptime BREATHE_OUT: Int32 = Int32(6)
comptime BREATHE_CYCLE: Int32 = BREATHE_IN + BREATHE_HOLD + BREATHE_OUT

comptime PAGE_DASH = "dash"
comptime PAGE_MILES = "miles"
comptime PAGE_SOS = "sos"
comptime PAGE_JOURNAL = "journal"
comptime PAGE_SETTINGS = "settings"

comptime JOURNAL_SHOWN: Int = 60

# What the about box says about the app itself.
#
# These three are the same in both languages, which is why they are not looked
# up: a version, a web address and a copyright notice are not interface text.
# The version has to be the one snapcraft.yaml declares, and the two are edited
# together by hand, because the app is a single binary with nothing at run time
# to read the version out of.
comptime APP_VERSION = "0.1.0"
comptime APP_WEBSITE = "https://github.com/lapisdecor/smokenot"
comptime APP_COPYRIGHT = "Copyright © 2026 Luís Louro"

def stylesheet() -> String:
    """The window's own styling, on top of whatever theme is installed."""
    var out = String("window { font-size: 11pt; }\n")
    out += String(
        ".card { background: alpha(currentColor, 0.05); border-radius: 12px; padding: 12px 14px; }\n"
    )
    out += String(".pill { border-radius: 999px; padding: 6px 16px; }\n")
    out += String(".numeric { font-family: monospace; font-size: 30pt; }\n")
    out += String(".heading { font-weight: bold; }\n")
    out += String(".milestone-mark { font-size: 15pt; min-width: 22px; }\n")
    out += String(".accent { color: #2a9d5c; }\n")
    out += String(".warning { color: #c2660a; }\n")
    return out^


# ------------------------------------------------------------ small helpers


def words(user_data: Widget) -> Translations:
    """The translations for the language the model is stored in."""
    return Translations(model_of(user_data)[].profile.language)


def label(user_data: Widget, key: String) -> String:
    return words(user_data).t(key)


def elapsed(user_data: Widget) -> Int64:
    """Seconds since the quit date, never negative."""
    var seconds = sys.now_epoch() - model_of(user_data)[].profile.quit_epoch
    if seconds < Int64(0):
        return Int64(0)
    return seconds


def days_elapsed(user_data: Widget) -> Int64:
    return elapsed(user_data) // SECONDS_PER_DAY


def language_label(lang: Int) -> String:
    """The name of the language a toggle switches *to*."""
    return String("English") if lang == LANG_PT else String("Português")


def read_entries(user_data: Widget) -> List[JournalEntry]:
    """The journal, or an empty one when it cannot be read."""
    try:
        return model_of(user_data)[].entries()
    except:
        return List[JournalEntry]()


def persist(user_data: Widget) -> Bool:
    """Write the model back to its file, reporting whether that worked."""
    try:
        save(sys.state_path(), model_of(user_data)[])
        return True
    except:
        return False


def set_button(button: Widget, value: String):
    if not is_null(button):
        gtk.button_set_label(button, value)


def set_label(widget: Widget, value: String):
    if not is_null(widget):
        gtk.label_set_text(widget, value)


def heading(text: String) -> Widget:
    var widget = gtk.label_new(text)
    gtk.widget_add_css_class(widget, "title-1")
    gtk.label_set_xalign(widget, c_float(0.0))
    return widget


def caption(text: String) -> Widget:
    """A small dim line, for the quiet parts of a page."""
    var widget = gtk.label_new(text)
    gtk.label_set_xalign(widget, c_float(0.0))
    gtk.widget_add_css_class(widget, "dim-label")
    gtk.label_set_wrap(widget, True)
    return widget


def body(text: String) -> Widget:
    var widget = gtk.label_new(text)
    gtk.label_set_xalign(widget, c_float(0.0))
    gtk.label_set_wrap(widget, True)
    gtk.label_set_selectable(widget, True)
    return widget


def page() -> Widget:
    """A padded vertical box, which is what every stack page is built into."""
    var box = gtk.box_new(gtk.ORIENTATION_VERTICAL, c_int(0))
    gtk.widget_set_margins(box, c_int(22))
    gtk.widget_set_hexpand(box, True)
    gtk.widget_set_vexpand(box, True)
    return box


def field_row(caption_text: String, field: Widget) -> Tuple[Widget, Widget]:
    """A caption above a field, with the caption handed back as well.

    Switching language rewrites captions in place, and the caption is a
    widget of its own inside the row, so the caller needs a handle on it.
    """
    var label = caption(caption_text)
    var box = gtk.box_new(gtk.ORIENTATION_VERTICAL, c_int(2))
    gtk.box_append(box, label)
    gtk.box_append(box, field)
    gtk.widget_set_hexpand(field, True)
    gtk.widget_set_margin_bottom(box, c_int(10))
    return (box, label)


def number_entry() -> Widget:
    var entry = gtk.entry_new()
    gtk.entry_set_alignment(entry, c_float(1.0))
    gtk.entry_set_width_chars(entry, c_int(8))
    return entry


def stat_tile(caption_text: String) -> Tuple[Widget, Widget]:
    """A card with a small caption over a big number.

    The number comes back second so the caller can keep updating it.
    """
    var box = gtk.box_new(gtk.ORIENTATION_VERTICAL, c_int(2))
    gtk.widget_add_css_class(box, "card")
    gtk.widget_set_hexpand(box, True)
    var top = caption(caption_text)
    gtk.widget_add_css_class(top, "heading")
    var value = gtk.label_new(String(""))
    gtk.widget_add_css_class(value, "title-2")
    gtk.label_set_xalign(value, c_float(0.0))
    gtk.label_set_ellipsize(value, c_int(3))
    gtk.box_append(box, top)
    gtk.box_append(box, value)
    return (box, value)


def clear_children(container: Widget):
    """Empty a box so it can be filled again.

    GTK keeps children in a list with no call for its length, so the children
    are walked and removed one at a time.
    """
    var child = gtk.widget_get_first_child(container)
    while not is_null(child):
        var next = gtk.widget_get_next_sibling(child)
        gtk.box_remove(container, child)
        child = next


# ------------------------------------------------------------ the dashboard


def days_until(user_data: Widget) -> Int64:
    """Whole days between now and a quit date that has not arrived yet."""
    var seconds = model_of(user_data)[].profile.quit_epoch - sys.now_epoch()
    if seconds <= Int64(0):
        return Int64(0)
    return (seconds + SECONDS_PER_DAY - Int64(1)) // SECONDS_PER_DAY


def is_quit_today(user_data: Widget) -> Bool:
    """Whether the chosen quit day is the day going by.

    Counted on the calendar rather than the clock, so a date stored at midnight
    still counts as today for the whole day, and the button stays on screen from
    the first tick after midnight to the last one before the next midnight.
    """
    return model_of(user_data)[].profile.is_quit_day(sys.now_epoch())


def refresh_dashboard(user_data: Widget):
    var ui = ui_of(user_data)
    var t = words(user_data)
    var model = model_of(user_data)
    var now = sys.now_epoch()
    var seconds = elapsed(user_data)
    var gains = model[].profile.gains(now)
    var quit_epoch = model[].profile.quit_epoch
    # The button belongs to one moment only: the chosen day, before the count
    # has begun. Every other state hides it.
    var show_quit_now = False

    if quit_epoch <= Int64(0):
        # No date has been chosen yet, so the dashboard has nothing to count
        # from. The figures are zero rather than the 1970 epoch, and the window
        # is on the settings page anyway until the profile is saved.
        set_label(ui[].dash_days, String(""))
        set_label(ui[].dash_since, String(""))
    elif is_quit_today(user_data):
        # The day is here and nothing has been counted yet, so the headline
        # says the day has arrived and the button is the answer. Quitting is
        # the one thing on this page the user has to do themselves.
        set_label(ui[].dash_days, t.t("dash_starts_today"))
        set_label(ui[].dash_since, t.t("dash_starts_on") + sys.local_date(quit_epoch))
        show_quit_now = True
    elif model[].profile.is_planned(now):
        # Nothing has been gained yet, so the headline is the wait instead of a
        # row of zeros pretending otherwise.
        set_label(ui[].dash_days, t.t("dash_starts_in") + t.days(days_until(user_data)))
        set_label(ui[].dash_since, t.t("dash_starts_on") + sys.local_date(quit_epoch))
    else:
        set_label(ui[].dash_days, t.days(gains.days))
        set_label(ui[].dash_since, t.t("dash_since") + " " + sys.local_date(quit_epoch))
    gtk.widget_set_visible(ui[].dash_quit_now, show_quit_now)
    set_label(ui[].dash_money, t.amount(gains.money))
    set_label(ui[].dash_cigs, t.cigarettes(gains.whole_cigarettes()))
    set_label(ui[].dash_life, t.minutes(gains.whole_life_minutes()))

    var key = milestones.summary_key(seconds)
    if key == "":
        set_label(ui[].dash_next, t.t("milestone_15y"))
        set_label(ui[].dash_next_in, String(""))
    else:
        set_label(ui[].dash_next, t.t("dash_next_milestone") + " · " + t.t(key))
        set_label(
            ui[].dash_next_in,
            milestones.elapsed_label(milestones.next_seconds_remaining(seconds)),
        )
    gtk.progress_bar_set_fraction(
        ui[].dash_bar, c_double(milestones.progress(seconds))
    )


def build_dashboard(user_data: Widget) -> Widget:
    var ui = ui_of(user_data)
    var t = words(user_data)
    var box = page()

    var days = gtk.label_new(String(""))
    gtk.widget_add_css_class(days, "title-1")
    gtk.label_set_xalign(days, c_float(0.0))
    ui[].dash_days = days
    var since = caption(String(""))
    ui[].dash_since = since
    gtk.widget_set_margin_top(since, c_int(2))
    gtk.box_append(box, heading(t.t("dash_title")))
    gtk.box_append(box, days)
    gtk.box_append(box, since)

    var row = gtk.box_new(gtk.ORIENTATION_HORIZONTAL, c_int(10))
    var money = stat_tile(t.t("dash_money"))
    var cigs = stat_tile(t.t("dash_cigs"))
    var life = stat_tile(t.t("dash_life"))
    var slips = stat_tile(t.t("journal_slip"))
    ui[].dash_money = money[1]
    ui[].dash_cigs = cigs[1]
    ui[].dash_life = life[1]
    ui[].dash_slips = slips[1]
    gtk.box_append(row, money[0])
    gtk.box_append(row, cigs[0])
    gtk.box_append(row, life[0])
    gtk.box_append(row, slips[0])
    gtk.widget_set_margin_top(row, c_int(14))
    gtk.box_append(box, row)

    var next_name = gtk.label_new(String(""))
    gtk.label_set_xalign(next_name, c_float(0.0))
    ui[].dash_next = next_name
    var next_in = gtk.label_new(String(""))
    gtk.widget_add_css_class(next_in, "dim-label")
    ui[].dash_next_in = next_in
    var next_row = gtk.box_new(gtk.ORIENTATION_HORIZONTAL, c_int(8))
    gtk.box_append(next_row, next_name)
    gtk.box_append(next_row, next_in)

    var bar = gtk.progress_bar_new()
    gtk.progress_bar_set_show_text(bar, False)
    ui[].dash_bar = bar
    var progress = gtk.box_new(gtk.ORIENTATION_VERTICAL, c_int(4))
    gtk.box_append(progress, next_row)
    gtk.box_append(progress, bar)
    gtk.widget_set_margin_top(progress, c_int(16))
    gtk.box_append(box, progress)

    var note = caption(t.t("dash_encouragement"))
    ui[].dash_note = note
    gtk.widget_set_margin_top(note, c_int(16))
    gtk.box_append(box, note)

    # The button is what starts a count the user chose a day for: it appears on
    # that day and nowhere else, so the act of quitting is a press and not a
    # date quietly passing. It is left aligned like the rest of the page, so
    # the pill keeps its own shape instead of stretching across it.
    var quit_now = gtk.button_new(t.t("dash_quit_now"))
    gtk.widget_add_css_class(quit_now, "pill")
    gtk.widget_add_css_class(quit_now, "suggested-action")
    gtk.widget_set_halign(quit_now, gtk.ALIGN_START)
    gtk.widget_set_visible(quit_now, False)
    ui[].dash_quit_now = quit_now
    gtk.widget_set_margin_top(quit_now, c_int(16))
    gtk.box_append(box, quit_now)
    return box


def quit_now(user_data: Widget):
    """Start the count from this moment, for a day that has arrived.

    The date chose the day and this press chooses the hour, so the moment is
    stamped here rather than read back from the calendar. Everything that shows
    a figure counted from that moment is refreshed, which is also what takes the
    button back off the screen.
    """
    var model = model_of(user_data)
    model[].profile.start_counting(sys.now_epoch())
    _ = persist(user_data)
    refresh_dashboard(user_data)
    refresh_milestones(user_data)
    refresh_settings(user_data)


# ------------------------------------------------------------ the timeline


def refresh_milestones(user_data: Widget):
    var ui = ui_of(user_data)
    var t = words(user_data)
    var seconds = elapsed(user_data)
    var list = milestones.all()
    clear_children(ui[].miles_box)

    set_label(
        ui[].miles_done,
        t.integer(Int64(milestones.reached_count(seconds)))
        + " / "
        + t.integer(Int64(len(list))),
    )
    for index in range(len(list)):
        var done = seconds >= list[index].seconds
        var row = gtk.box_new(gtk.ORIENTATION_HORIZONTAL, c_int(10))
        gtk.widget_set_hexpand(row, True)

        var mark = gtk.label_new(String("✓") if done else String("•"))
        gtk.widget_add_css_class(mark, "milestone-mark")
        if done:
            gtk.widget_add_css_class(mark, "accent")
        gtk.box_append(row, mark)

        var name = gtk.label_new(t.t(list[index].key))
        gtk.label_set_xalign(name, c_float(0.0))
        gtk.label_set_hexpand(name, True)
        gtk.box_append(row, name)

        var when = gtk.label_new(milestones.elapsed_label(list[index].seconds))
        gtk.widget_add_css_class(when, "dim-label")
        gtk.box_append(row, when)
        gtk.box_append(ui[].miles_box, row)


def build_milestones(user_data: Widget) -> Widget:
    var ui = ui_of(user_data)
    var t = words(user_data)
    var box = page()
    gtk.box_append(box, heading(t.t("milestones_title")))

    var done = caption(String(""))
    ui[].miles_done = done
    gtk.widget_set_margin_top(done, c_int(4))
    gtk.box_append(box, done)

    var list = gtk.box_new(gtk.ORIENTATION_VERTICAL, c_int(8))
    ui[].miles_box = list
    var scroll = gtk.scrolled_window_new(False, True)
    gtk.scrolled_window_set_child(scroll, list)
    gtk.widget_set_vexpand(scroll, True)
    gtk.widget_set_margin_top(scroll, c_int(10))
    gtk.box_append(box, scroll)
    gtk.box_append(box, caption(t.t("milestones_disclaimer")))
    refresh_milestones(user_data)
    return box


# ------------------------------------------------------------ the craving timer


def clock_text(seconds: Int32) -> String:
    var left = seconds
    if left < Int32(0):
        left = Int32(0)
    var rest = format_int(Int64(left % Int32(60)))
    if left % Int32(60) < Int32(10):
        rest = String("0") + rest
    return format_int(Int64(left // Int32(60))) + String(":") + rest


def breathe_size(phase: Int32) -> Float64:
    """How far the breathing circle has grown, 0.2 to 1.0 of its box."""
    var cycle = phase % BREATHE_CYCLE
    if cycle < BREATHE_IN:
        return Float64(cycle) / Float64(BREATHE_IN) * Float64(0.8) + Float64(0.2)
    if cycle < BREATHE_IN + BREATHE_HOLD:
        return Float64(1.0)
    var out = cycle - (BREATHE_IN + BREATHE_HOLD)
    return Float64(BREATHE_OUT - out) / Float64(BREATHE_OUT) * Float64(0.8) + Float64(0.2)


def phase_key(phase: Int32) -> String:
    var cycle = phase % BREATHE_CYCLE
    if cycle < BREATHE_IN:
        return "craving_inhale"
    if cycle < BREATHE_IN + BREATHE_HOLD:
        return "craving_hold"
    return "craving_exhale"


def refresh_sos(user_data: Widget):
    var ui = ui_of(user_data)
    var t = words(user_data)
    if ui[].sos_running == Int32(0):
        set_label(ui[].sos_clock, clock_text(SOS_SECONDS))
        set_label(ui[].sos_phase, t.t("craving_breathe_hint"))
        set_label(ui[].sos_body, t.t("craving_body"))
        gtk.widget_set_sensitive(ui[].sos_start, True)
        gtk.widget_set_sensitive(ui[].sos_stop, False)
        return
    set_label(ui[].sos_clock, clock_text(ui[].sos_left))
    set_label(ui[].sos_phase, t.t(phase_key(ui[].breathe)))
    set_label(ui[].sos_body, t.t("craving_move"))
    gtk.widget_set_sensitive(ui[].sos_start, False)
    gtk.widget_set_sensitive(ui[].sos_stop, True)


def build_sos(user_data: Widget) -> Widget:
    var ui = ui_of(user_data)
    var t = words(user_data)
    var box = page()
    gtk.box_append(box, heading(t.t("craving_title")))

    var intro = body(t.t("craving_body"))
    ui[].sos_body = intro
    gtk.widget_set_margin_top(intro, c_int(6))
    gtk.box_append(box, intro)

    var area = gtk.drawing_area_new()
    gtk.drawing_area_set_size(area, c_int(240), c_int(240))
    gtk.widget_set_halign(area, gtk.ALIGN_CENTER)
    gtk.widget_set_valign(area, gtk.ALIGN_CENTER)
    gtk.widget_set_vexpand(area, True)
    ui[].sos_area = area

    var clock = gtk.label_new(String(""))
    gtk.widget_add_css_class(clock, "numeric")
    gtk.widget_set_halign(clock, gtk.ALIGN_CENTER)
    ui[].sos_clock = clock
    var phase = gtk.label_new(String(""))
    gtk.widget_add_css_class(phase, "dim-label")
    gtk.widget_set_halign(phase, gtk.ALIGN_CENTER)
    ui[].sos_phase = phase

    var middle = gtk.box_new(gtk.ORIENTATION_VERTICAL, c_int(4))
    gtk.box_append(middle, area)
    gtk.box_append(middle, clock)
    gtk.box_append(middle, phase)
    gtk.box_append(box, middle)

    var buttons = gtk.box_new(gtk.ORIENTATION_HORIZONTAL, c_int(8))
    gtk.widget_set_halign(buttons, gtk.ALIGN_CENTER)
    var start = gtk.button_new(t.t("craving_start"))
    gtk.widget_add_css_class(start, "pill")
    gtk.widget_add_css_class(start, "suggested-action")
    ui[].sos_start = start
    var stop = gtk.button_new(t.t("craving_stop"))
    gtk.widget_add_css_class(stop, "pill")
    ui[].sos_stop = stop
    # Logging a craving or a slip is the journal's business, and it has its
    # buttons there, so this page only runs the timer.
    gtk.box_append(buttons, start)
    gtk.box_append(buttons, stop)
    gtk.widget_set_margin_top(buttons, c_int(10))
    gtk.box_append(box, buttons)
    refresh_sos(user_data)
    return box


# ------------------------------------------------------------ the journal


def when_label(user_data: Widget, epoch: Int64) -> String:
    """A journal entry's time, counted back from now in whole units."""
    var t = words(user_data)
    var days = (sys.now_epoch() - epoch) // SECONDS_PER_DAY
    if days <= Int64(0):
        return t.t("field_now")
    if days < Int64(30):
        return t.integer(days) + String(" ") + t.t("field_days_ago")
    if days < Int64(365):
        return t.months(days // Int64(30))
    return t.years(days // Int64(365))


def refresh_journal(user_data: Widget):
    """Rewrite the journal list.

    Reading the journal can only fail if memory runs out, and the callers here
    are GTK callbacks, which are not allowed to fail: a journal that cannot be
    read is shown as empty instead.
    """
    var ui = ui_of(user_data)
    var t = words(user_data)
    clear_children(ui[].journal_box)
    var entries = read_entries(user_data)
    set_label(
        ui[].journal_count,
        t.integer(Int64(len(entries))) + " " + t.t("journal_count"),
    )
    if len(entries) == 0:
        gtk.box_append(ui[].journal_box, caption(t.t("journal_empty")))
        return

    var shown = len(entries)
    if shown > JOURNAL_SHOWN:
        shown = JOURNAL_SHOWN
    for index in range(shown):
        var entry = entries[index]
        var row = gtk.box_new(gtk.ORIENTATION_VERTICAL, c_int(2))
        gtk.widget_add_css_class(row, "card")

        var top = gtk.box_new(gtk.ORIENTATION_HORIZONTAL, c_int(8))
        var kind = gtk.label_new(
            t.t("journal_slip") if entry.is_slip() else t.t("journal_craving")
        )
        gtk.widget_add_css_class(kind, "heading")
        if entry.is_slip():
            gtk.widget_add_css_class(kind, "warning")
        var when = gtk.label_new(when_label(user_data, entry.epoch))
        gtk.widget_add_css_class(when, "dim-label")
        gtk.label_set_xalign(when, c_float(1.0))
        gtk.label_set_hexpand(when, True)
        gtk.box_append(top, kind)
        gtk.box_append(top, when)
        gtk.box_append(row, top)

        if entry.note.byte_length() > 0:
            gtk.box_append(row, body(String(entry.note)))
        gtk.box_append(ui[].journal_box, row)


def log_entry(user_data: Widget, kind: Int):
    var ui = ui_of(user_data)
    var model = model_of(user_data)
    var note = gtk.entry_get_text(ui[].journal_note)
    try:
        model[].add_entry(sys.now_epoch(), kind, note)
    except:
        return
    gtk.entry_set_text(ui[].journal_note, String(""))
    _ = persist(user_data)
    refresh_journal(user_data)
    refresh_dashboard(user_data)


def build_journal(user_data: Widget) -> Widget:
    var ui = ui_of(user_data)
    var t = words(user_data)
    var box = page()
    gtk.box_append(box, heading(t.t("journal_title")))

    var count = caption(String(""))
    ui[].journal_count = count
    gtk.widget_set_margin_top(count, c_int(4))
    gtk.box_append(box, count)

    var entry = gtk.entry_new()
    gtk.entry_set_placeholder(entry, t.t("journal_note_hint"))
    gtk.entry_set_max_length(entry, c_int(200))
    ui[].journal_note = entry
    gtk.box_append(box, field_row(t.t("journal_note"), entry)[0])

    var buttons = gtk.box_new(gtk.ORIENTATION_HORIZONTAL, c_int(8))
    var craving = gtk.button_new(t.t("journal_craving"))
    gtk.widget_add_css_class(craving, "pill")
    var slip = gtk.button_new(t.t("journal_slip"))
    gtk.widget_add_css_class(slip, "pill")
    gtk.widget_add_css_class(slip, "destructive-action")
    gtk.box_append(buttons, craving)
    gtk.box_append(buttons, slip)
    gtk.box_append(box, buttons)
    ui[].journal_craving_button = craving
    ui[].journal_slip_button = slip

    var list = gtk.box_new(gtk.ORIENTATION_VERTICAL, c_int(8))
    ui[].journal_box = list
    var scroll = gtk.scrolled_window_new(False, True)
    gtk.scrolled_window_set_child(scroll, list)
    gtk.widget_set_vexpand(scroll, True)
    gtk.widget_set_margin_top(scroll, c_int(12))
    gtk.box_append(box, scroll)
    refresh_journal(user_data)
    return box


# ----------------------------------------------------------- every second


def tick(user_data: Widget):
    """What the window does once a second.

    The dashboard counts seconds, the craving timer counts down, and the
    calendar is read back: this GTK has no `day-selected` signal to say a day
    was clicked, so the property change is the quick path and this is the one
    that cannot be missed.
    """
    var ui = ui_of(user_data)
    refresh_dashboard(user_data)
    if ui[].sos_running != Int32(0):
        ui[].sos_left -= Int32(1)
        ui[].breathe += Int32(1)
        if ui[].sos_left <= Int32(0):
            ui[].sos_left = Int32(0)
            ui[].sos_running = Int32(0)
            ui[].breathe = Int32(0)
            set_label(ui[].sos_body, label(user_data, "craving_done_title"))
        else:
            set_label(ui[].sos_body, label(user_data, "craving_body"))
        refresh_sos(user_data)
        gtk.widget_queue_draw(ui[].sos_area)
    refresh_date_caption(user_data)


# ------------------------------------------------------ the settings page



def today_midnight() -> Int64:
    """Local midnight of the current day, the default day to pick."""
    var now = sys.now_epoch()
    var today = sys.local_time(now)
    return sys.local_midnight(today.year, today.month, today.day)


def date_caption(user_data: Widget, epoch: Int64) -> String:
    """The picked day in the user's own words, and the date beside it.

    Relative on the left, because "Tomorrow" is what the choice means to the
    person making it, and the plain date on the right, because a day count is
    only ever as good as the day it is counted from.
    """
    var t = words(user_data)
    # Counted on the calendar, not on the clock: a day that is under a day old
    # is still yesterday, and yesterday is not tomorrow.
    var days = sys.local_day_number(sys.now_epoch()) - sys.local_day_number(epoch)
    if days < Int64(0):
        return t.t("date_in_days") + t.days(-days) + " · " + sys.local_date(epoch)
    if days == Int64(0):
        return t.t("field_now") + " · " + sys.local_date(epoch)
    if days == Int64(1):
        return t.t("field_yesterday") + " · " + sys.local_date(epoch)
    if days < Int64(30):
        return t.days(days) + " " + t.t("field_days_ago") + " · " + sys.local_date(epoch)
    return sys.local_date(epoch)


def days_in_month(year: Int64, month: Int64) -> Int64:
    """How many days a month has, February included.

    The grid is handed whole years and months one at a time, and a day that the
    month it is moving to does not have would be refused by GTK, so the day is
    checked against the month before it goes in.
    """
    if month == Int64(2):
        if year % Int64(4) == Int64(0) and (
            year % Int64(100) != Int64(0) or year % Int64(400) == Int64(0)
        ):
            return Int64(29)
        return Int64(28)
    if month == Int64(4) or month == Int64(6) or month == Int64(9) or month == Int64(11):
        return Int64(30)
    return Int64(31)


def point_calendar(calendar: Widget, epoch: Int64):
    """Move the grid to a day, keeping the day inside the month it lands in."""
    var civil = sys.local_time(epoch)
    var day = civil.day
    var last = days_in_month(civil.year, civil.month)
    if day > last:
        day = last
    gtk.calendar_select(calendar, civil.year, civil.month - Int64(1), day)


def selected_date(user_data: Widget) -> Int64:
    """The day the calendar is on, as local midnight."""
    var picked = gtk.calendar_get_date(ui_of(user_data)[].settings_calendar)
    return sys.local_midnight(picked[0], picked[1] + Int64(1), picked[2])


def refresh_date_caption(user_data: Widget):
    """Name the day the grid is on, in the language the app is in."""
    set_label(
        ui_of(user_data)[].settings_date_caption,
        date_caption(user_data, selected_date(user_data)),
    )


def refresh_settings(user_data: Widget):
    """Put the calendar and the caption back in step with the model."""
    var ui = ui_of(user_data)
    var epoch = model_of(user_data)[].profile.quit_epoch
    if epoch <= Int64(0):
        epoch = today_midnight()
    point_calendar(ui[].settings_calendar, epoch)
    set_label(ui[].settings_date_caption, date_caption(user_data, epoch))


def fill_profile(user_data: Widget):
    """Show what is already stored, so an edit starts from the truth.

    A profile that has never been filled in falls back to the same suggestion
    the model carries, which is why the boxes are never simply empty.
    """
    var ui = ui_of(user_data)
    var profile = model_of(user_data)[].profile
    gtk.entry_set_text(ui[].settings_cigs, format_int(profile.cigs_per_day))
    gtk.entry_set_text(ui[].settings_pack_size, format_int(profile.pack_size))
    gtk.entry_set_text(
        ui[].settings_pack_price, format_fixed(profile.pack_price, 2)
    )


def typed_price(text: String) -> Float64:
    """A price as a person typed it, in either decimal convention.

    The box is filled with a dot, but a Portuguese keyboard has a comma, so one
    comma with no dot is the decimal mark rather than a stray character to stop
    at. Anything left over is ignored by the parser, and a price that is not a
    number at all comes back as zero, which the save refuses.
    """
    var body = String(text.strip())
    if body.find(",") >= 0 and body.find(".") < 0:
        body = body.replace(",", ".")
    return parse_float(body)


def save_profile(user_data: Widget):
    """Store the settings page and move on to the dashboard.

    A field that is empty or not a number stops the whole thing: storing half
    a profile would put figures on the dashboard that the user never entered.
    """
    var ui = ui_of(user_data)
    var model = model_of(user_data)
    var t = words(user_data)

    var text = gtk.entry_get_text(ui[].settings_cigs)
    if text.byte_length() == 0:
        set_label(ui[].settings_status, t.t("error_positive"))
        return
    var cigs = parse_int(text)
    if cigs <= Int64(0):
        set_label(ui[].settings_status, t.t("error_invalid"))
        return

    # The other two numbers are read the same way rather than quietly falling
    # back to a default: a pack of 7,50 that was never parsed is a habit
    # counted at 7, and the user would never see the difference.
    var size_text = gtk.entry_get_text(ui[].settings_pack_size)
    if size_text.byte_length() == 0 or parse_int(size_text) <= Int64(0):
        set_label(ui[].settings_status, t.t("error_positive"))
        return
    var price_text = gtk.entry_get_text(ui[].settings_pack_price)
    if price_text.byte_length() == 0 or typed_price(price_text) <= Float64(0.0):
        set_label(ui[].settings_status, t.t("error_positive"))
        return

    var now = sys.now_epoch()
    var profile = model[].profile
    profile.cigs_per_day = cigs
    profile.pack_size = parse_int(size_text)
    profile.pack_price = typed_price(price_text)
    profile.set_quit_day(selected_date(user_data), now)
    if profile.created_epoch <= Int64(0):
        profile.created_epoch = now
    profile.mark_configured()
    profile.clamp()
    model[].profile = profile
    _ = persist(user_data)
    set_label(ui[].settings_status, String(""))
    fill_profile(user_data)
    retitle(user_data)
    show_main(user_data)


def build_settings(user_data: Widget) -> Widget:
    """The one page that sets up the app, and the first one it opens on.

    The habits, the day they stop, the language and everything else about the
    profile live here and nowhere else, so there is a single place to look when
    something needs changing. It is a tall page with a calendar on it, which is
    why it scrolls.
    """
    var ui = ui_of(user_data)
    var t = words(user_data)
    var box = page()

    var title = heading(t.t("settings_title"))
    ui[].settings_heading = title
    gtk.box_append(box, title)

    var intro = body(t.t("settings_intro"))
    ui[].settings_intro = intro
    gtk.widget_set_margin_top(intro, c_int(4))
    gtk.box_append(box, intro)

    var language = gtk.check_button_new(
        language_label(model_of(user_data)[].profile.language)
    )
    ui[].settings_lang = language
    var language_row = field_row(t.t("settings_language"), language)
    ui[].settings_language_label = language_row[1]
    gtk.box_append(box, language_row[0])

    var cigs = number_entry()
    ui[].settings_cigs = cigs
    var cigs_row = field_row(t.t("field_cigs_per_day"), cigs)
    ui[].settings_cigs_label = cigs_row[1]
    gtk.box_append(box, cigs_row[0])

    var size = number_entry()
    ui[].settings_pack_size = size
    var size_row = field_row(t.t("field_pack_size"), size)
    ui[].settings_pack_size_label = size_row[1]
    gtk.box_append(box, size_row[0])

    var price = number_entry()
    ui[].settings_pack_price = price
    var price_row = field_row(t.t("field_pack_price"), price)
    ui[].settings_pack_price_label = price_row[1]
    gtk.box_append(box, price_row[0])

    # The calendar is the date control: the grid, the arrows on it and the
    # caption under it are the whole of it. Its own month name follows the
    # system locale, which is why the caption repeats the date in the app's
    # language.
    var calendar = gtk.calendar_new()
    ui[].settings_calendar = calendar
    gtk.calendar_set_heading(calendar, True)
    gtk.calendar_set_day_names(calendar, True)
    gtk.calendar_set_week_numbers(calendar, False)
    gtk.widget_set_halign(calendar, gtk.ALIGN_START)
    var date_row = field_row(t.t("field_quit_date"), calendar)
    ui[].settings_date_label = date_row[1]
    gtk.box_append(box, date_row[0])

    var chosen = caption(String(""))
    ui[].settings_date_caption = chosen
    gtk.box_append(box, chosen)

    var status = body(String(""))
    ui[].settings_status = status
    gtk.widget_set_margin_top(status, c_int(4))
    gtk.box_append(box, status)

    var save = gtk.button_new(t.t("settings_save"))
    gtk.widget_add_css_class(save, "pill")
    gtk.widget_add_css_class(save, "suggested-action")
    gtk.widget_set_halign(save, gtk.ALIGN_END)
    ui[].settings_save = save
    gtk.box_append(box, save)

    var path = caption(sys.state_path())
    ui[].settings_path = path
    var path_row = field_row(t.t("settings_data_path"), path)
    gtk.box_append(box, path_row[0])

    var about = body(t.t("settings_about_body") + String(" ") + t.t("settings_health_source"))
    ui[].settings_about = about
    gtk.box_append(box, field_row(t.t("settings_about"), about)[0])

    var reset = gtk.button_new(t.t("settings_reset"))
    gtk.widget_add_css_class(reset, "destructive-action")
    gtk.widget_set_halign(reset, gtk.ALIGN_START)
    ui[].settings_reset = reset
    gtk.box_append(box, reset)

    # The about box sits on the other side of the page from the one button
    # that destroys things, so the two are not neighbours by accident.
    var about_button = gtk.button_new(t.t("settings_about"))
    gtk.widget_add_css_class(about_button, "pill")
    gtk.widget_set_halign(about_button, gtk.ALIGN_END)
    ui[].settings_about_button = about_button
    gtk.box_append(box, about_button)

    var scroll = gtk.scrolled_window_new(False, True)
    gtk.scrolled_window_set_child(scroll, box)
    gtk.widget_set_vexpand(scroll, True)
    fill_profile(user_data)
    refresh_settings(user_data)
    return scroll


def build_about(user_data: Widget) -> Tuple[Widget, Widget]:
    """The about box: which app, which version, and under what terms.

    It is a window of its own rather than another row on the settings page,
    because that is where a person looks for it and because the licence text is
    longer than a card wants to hold. It belongs to the window it was opened
    from and holds it up while it is there, so there is one thing to close.

    Nothing in it can be clicked. A link would want a browser, a browser wants
    a portal, and a strict snap with no dbus plug has neither, so the address
    and the licence are printed to be read and copied instead.

    The close button comes back second, because `ui.handlers` is what wires it
    and the wiring is not this file's business.
    """
    var t = words(user_data)
    var win = gtk.window_new()
    gtk.window_set_title(win, t.t("about_title"))
    gtk.window_set_transient_for(win, ui_of(user_data)[].window)
    gtk.window_set_modal(win, True)
    gtk.window_set_default_size(win, c_int(460), c_int(0))

    var box = gtk.box_new(gtk.ORIENTATION_VERTICAL, c_int(0))
    gtk.widget_set_margins(box, c_int(20))
    gtk.widget_set_hexpand(box, True)

    var name = heading(t.t("app_name") + String(" ") + String(APP_VERSION))
    gtk.box_append(box, name)

    var tagline = caption(t.t("app_tagline"))
    gtk.box_append(box, tagline)

    var holder = caption(APP_COPYRIGHT)
    gtk.widget_set_margin_top(holder, c_int(6))
    gtk.box_append(box, holder)

    var website = body(t.t("about_website") + String(": ") + String(APP_WEBSITE))
    gtk.widget_set_margin_top(website, c_int(6))
    gtk.box_append(box, website)

    var licence = body(t.t("about_license"))
    gtk.widget_set_margin_top(licence, c_int(6))
    gtk.box_append(box, licence)

    var close = gtk.button_new(t.t("common_close"))
    gtk.widget_add_css_class(close, "pill")
    gtk.widget_add_css_class(close, "suggested-action")
    gtk.widget_set_halign(close, gtk.ALIGN_END)
    gtk.widget_set_margin_top(close, c_int(14))
    gtk.box_append(box, close)

    gtk.window_set_default_widget(win, close)
    gtk.window_set_child(win, box)
    return (win, close)


# ------------------------------------------------------------ assembling


def apply_style(window: Widget):
    """Install the stylesheet, so the window looks the same everywhere."""
    var provider = gtk.css_provider_new()
    gtk.css_provider_load_from_string(provider, stylesheet())
    gtk.style_add_provider(window, provider, STYLE_PRIORITY)


def show_main(user_data: Widget):
    """Hand the window over to the app itself: the dashboard and the tabs.

    This is what a saved profile gets, which is also what finishing the setup
    page gets, so the two are the same moment from the user's point of view.
    """
    var ui = ui_of(user_data)
    gtk.widget_set_visible(ui[].switcher, True)
    gtk.stack_set_visible_child(ui[].stack, PAGE_DASH)
    refresh_dashboard(user_data)
    refresh_milestones(user_data)
    refresh_journal(user_data)


def show_setup(user_data: Widget):
    """The window before there is anything to count: the settings page alone.

    The tabs stay hidden because there is nothing behind them yet: a dashboard
    with no profile under it is a page of zeros, and a milestone list measured
    from a day that has not been chosen is worse than nothing.
    """
    var ui = ui_of(user_data)
    gtk.widget_set_visible(ui[].switcher, False)
    gtk.stack_set_visible_child(ui[].stack, PAGE_SETTINGS)
    refresh_settings(user_data)


def build_stack(user_data: Widget) -> Widget:
    var ui = ui_of(user_data)
    var t = words(user_data)
    var stack = gtk.stack_new()
    ui[].stack = stack

    gtk.stack_add_titled(
        stack, build_dashboard(user_data), PAGE_DASH, t.t("nav_dashboard")
    )
    gtk.stack_add_titled(
        stack, build_milestones(user_data), PAGE_MILES, t.t("nav_milestones")
    )
    gtk.stack_add_titled(stack, build_sos(user_data), PAGE_SOS, t.t("nav_quit"))
    gtk.stack_add_titled(
        stack, build_journal(user_data), PAGE_JOURNAL, t.t("nav_journal")
    )
    gtk.stack_add_titled(
        stack, build_settings(user_data), PAGE_SETTINGS, t.t("nav_settings")
    )

    var switcher = gtk.stack_switcher_new()
    gtk.stack_switcher_set_stack(switcher, stack)
    ui[].switcher = switcher
    return stack


def retitle(user_data: Widget):
    """Rewrite the text that is not a number, after a language change."""
    var ui = ui_of(user_data)
    var t = words(user_data)

    gtk.window_set_title(ui[].window, t.t("app_name") + String(" · ") + t.t("app_tagline"))
    gtk.stack_set_title(ui[].stack, PAGE_DASH, t.t("nav_dashboard"))
    gtk.stack_set_title(ui[].stack, PAGE_MILES, t.t("nav_milestones"))
    gtk.stack_set_title(ui[].stack, PAGE_SOS, t.t("nav_quit"))
    gtk.stack_set_title(ui[].stack, PAGE_JOURNAL, t.t("nav_journal"))
    gtk.stack_set_title(ui[].stack, PAGE_SETTINGS, t.t("nav_settings"))

    set_label(ui[].settings_heading, t.t("settings_title"))
    set_label(ui[].settings_intro, t.t("settings_intro"))
    set_label(ui[].settings_status, String(""))
    set_label(ui[].settings_cigs_label, t.t("field_cigs_per_day"))
    set_label(ui[].settings_pack_size_label, t.t("field_pack_size"))
    set_label(ui[].settings_pack_price_label, t.t("field_pack_price"))
    set_label(ui[].settings_language_label, t.t("settings_language"))
    set_label(ui[].settings_date_label, t.t("field_quit_date"))
    # Starting out and changing your mind are different jobs, so the button
    # says which one this is: the first save starts the count, a later one
    # only saves the change.
    set_button(
        ui[].settings_save,
        t.t("common_save") if model_of(user_data)[].profile.is_configured() else t.t(
            "settings_save"
        ),
    )
    gtk.check_button_set_label(
        ui[].settings_lang, language_label(t.lang)
    )
    set_button(ui[].sos_start, t.t("craving_start"))
    set_button(ui[].sos_stop, t.t("craving_stop"))
    set_button(ui[].dash_quit_now, t.t("dash_quit_now"))
    set_label(ui[].dash_note, t.t("dash_encouragement"))
    set_label(
        ui[].settings_about,
        t.t("settings_about_body") + String(" ") + t.t("settings_health_source"),
    )
    set_label(ui[].settings_path, sys.state_path())
    if ui[].reset_armed == Int32(0):
        gtk.button_set_label(ui[].settings_reset, t.t("settings_reset"))
    set_button(ui[].settings_about_button, t.t("settings_about"))

    var entry = ui[].journal_note
    if not is_null(entry):
        gtk.entry_set_placeholder(entry, t.t("journal_note_hint"))
    refresh_dashboard(user_data)
    refresh_milestones(user_data)
    refresh_journal(user_data)
    refresh_sos(user_data)
    refresh_settings(user_data)
    gtk.widget_queue_draw(ui[].sos_area)


def build_all(user_data: Widget):
    """Build the whole window and show it.

    Widgets only exist after GTK has started, so this is the first thing that
    touches one. The window is an ordinary window rather than an application
    window: an application window would want a name on the session bus, and a
    strict snap is not allowed to own one.

    A profile that is not set up yet opens on the settings page on its own,
    because the dashboard has nothing to show without one. Everything else
    opens on the dashboard.
    """
    var ui = ui_of(user_data)
    var model = model_of(user_data)
    var t = words(user_data)

    var window = gtk.window_new()
    ui[].window = window
    gtk.window_set_title(window, t.t("app_name") + String(" · ") + t.t("app_tagline"))
    gtk.window_set_default_size(window, c_int(760), c_int(640))
    apply_style(window)

    var root = gtk.box_new(gtk.ORIENTATION_VERTICAL, c_int(0))
    var header = gtk.box_new(gtk.ORIENTATION_HORIZONTAL, c_int(8))
    var name = heading(t.t("app_name"))
    gtk.widget_set_hexpand(name, True)
    gtk.widget_set_margin_start(name, c_int(18))
    gtk.widget_set_margin_top(name, c_int(10))
    # The language lives on the settings page and nowhere else, so there is
    # one control for it rather than two that disagree.
    gtk.box_append(header, name)

    var stack = build_stack(user_data)
    var switcher = ui[].switcher
    gtk.widget_set_margin_start(switcher, c_int(12))
    gtk.widget_set_margin_end(switcher, c_int(12))

    gtk.box_append(root, header)
    gtk.box_append(root, switcher)
    gtk.box_append(root, stack)
    gtk.widget_set_vexpand(stack, True)

    if model[].is_configured():
        show_main(user_data)
    else:
        show_setup(user_data)
    gtk.window_set_child(window, root)
    gtk.window_present(window)

    refresh_dashboard(user_data)
    if not model[].is_configured():
        refresh_sos(user_data)
