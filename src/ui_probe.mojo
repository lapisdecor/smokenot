# Copyright (C) 2026 Luís Louro
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Licensed under the GNU General Public License, version 3 or later. The full
# text is in LICENSE.

"""Driving the finished app without a person in front of it.

This starts the real application, waits for the window to be up, and then
plays the part of the user: fills the settings page in, picks a day on the
calendar, starts and stops a craving session, logs a craving and a slip,
switches language and resets. The buttons are activated the way a click or a
keyboard press activates them, so the callbacks run for real.

It is a test of the wiring rather than of the drawing. Point `XDG_DATA_HOME`
at a scratch directory to keep the saved state out of the way; the probe
removes its own file at the end.
"""

from gtk import gtk
from i18n.strings import LANG_PT
from lib import sys
from model.state import State
from std.ffi import c_double, c_int, c_uint, c_ulong, external_call
from tests import harness
from ui import app, host, screens
from ui.host import Widget, model_of, ui_of

comptime SETTLE_MS: c_uint = c_uint(400)


@always_inline("nodebug")
def on_settled(user_data: Widget) abi("C") -> c_int:
    """Run the checks once the window is up, then let the app close.

    The first return value stops the timer; the second closes the window, so
    the application loop finishes on its own and `main` can report.
    """
    # A GTK callback cannot fail, so anything the checks raise is caught here
    # and turned into a failed run rather than an error escaping the callback.
    try:
        run_checks(user_data)
    except:
        print("not ok - the checks could not finish")
    # `gtk_window_close` hands back nothing in GTK4, so the wrapper says so and
    # there is nothing to assign.
    gtk.window_close(ui_of(user_data)[].window)
    return c_int(0)


@always_inline("nodebug")
def click_it(target: Widget, signal: StringLiteral):
    """Finish a button gesture the way GTK does when it ends.

    A press with the mouse ends in `clicked` and Enter or space ends in
    `activate`, so the checks use `clicked` for what a person does with a
    mouse, and one `activate` below to keep the keyboard path honest too.
    Activating the widget instead would only ever test the keyboard.
    """
    _ = external_call["g_signal_emit_by_name", NoneType](target, signal.as_c_string_span())


def press(target: Widget):
    """Click a widget the way a mouse would, so the callback runs."""
    click_it(target, "clicked")


def press_key(target: Widget):
    """Enter or space on a focused button."""
    click_it(target, "activate")


def text_of(label: Widget) -> String:
    return gtk.label_get_text(label)


def show_page(user_data: Widget) -> String:
    return gtk.stack_get_visible_child(ui_of(user_data)[].stack)


def pick_day(calendar: Widget, year: Int64, month: Int64, day: Int64):
    """Choose a day on the grid, the way the window's own code does."""
    gtk.calendar_select(calendar, year, month, day)


def day_in(days: Int64) -> sys.CivilTime:
    """The calendar day `days` from today.

    Counted in days rather than in seconds, so a daylight saving switch in
    between cannot make "in three days" land on the wrong date, and a fixed day
    of the month cannot fall in the past depending on when the probe runs.
    """
    var target = sys.local_day_number(sys.now_epoch()) + days
    var step = sys.now_epoch()
    while sys.local_day_number(step) < target:
        step += Int64(86_400)
    while sys.local_day_number(step) > target:
        step -= Int64(86_400)
    return sys.local_time(step)


def pick_day_relative(calendar: Widget, days: Int64) -> Int64:
    """Put the grid on a day counted from today, and name where that is."""
    var civil = day_in(days)
    pick_day(calendar, civil.year, civil.month - Int64(1), civil.day)
    return sys.local_midnight(civil.year, civil.month, civil.day)


def run_checks(user_data: Widget) raises:
    var h = harness.Harness()
    harness.begin_suite(h, "ui")
    var ui = ui_of(user_data)

    # A profile that was never filled in opens on the settings page, on its
    # own, with the tabs out of the way.
    harness.check(
        h, show_page(user_data) == screens.PAGE_SETTINGS, "a new profile starts on settings"
    )
    harness.check(
        h, not gtk.widget_get_visible(ui[].switcher), "the tabs wait for a profile"
    )
    harness.check(
        h, text_of(ui[].settings_status).byte_length() == 0, "no nagging before anything is typed"
    )
    harness.check(
        h, not host.is_null(ui[].settings_calendar), "the date is picked on a calendar"
    )
    harness.check(
        h, not host.is_null(ui[].settings_cigs), "the habits have an answer box each"
    )
    harness.check(
        h,
        gtk.entry_get_text(ui[].settings_cigs).byte_length() > 0,
        "the boxes start on what is stored, not empty",
    )
    harness.check(
        h,
        text_of(ui[].settings_date_caption).byte_length() > 0,
        "the picked day is named under the calendar",
    )

    # An empty habits box stops the whole thing rather than storing half.
    gtk.entry_set_text(ui[].settings_cigs, String(""))
    press(ui[].settings_save)
    harness.check(
        h, not model_of(user_data)[].profile.is_configured(), "nothing is stored from an empty box"
    )
    harness.check(
        h, show_page(user_data) == screens.PAGE_SETTINGS, "a refused save stays on settings"
    )
    harness.check(
        h, text_of(ui[].settings_status).byte_length() > 0, "the status line explains what is missing"
    )

    # A day on the calendar, then a real save.
    var now = sys.now_epoch()
    gtk.entry_set_text(ui[].settings_cigs, String("20"))
    gtk.entry_set_text(ui[].settings_pack_size, String("20"))
    # A price with cents, because a pack of 7,50 that lands as 7 would count
    # the savings wrong without ever looking wrong.
    gtk.entry_set_text(ui[].settings_pack_price, String("seven"))
    press(ui[].settings_save)
    harness.check(
        h,
        not model_of(user_data)[].profile.is_configured()
        and show_page(user_data) == screens.PAGE_SETTINGS,
        "a price that is not a number is refused",
    )
    harness.check_float(
        h, screens.typed_price(String("7,50")), Float64(7.5), "a comma is a decimal mark too"
    )
    gtk.entry_set_text(ui[].settings_pack_price, String("7,50"))
    # A day three days out, so the plan is a plan whichever day the probe runs
    # on and a fixed date of the month cannot be behind us.
    var quit_day = pick_day_relative(ui[].settings_calendar, Int64(3))
    harness.check(
        h,
        screens.selected_date(user_data) == quit_day,
        "the calendar's day is the day that gets read",
    )
    # The window notices a picked day on its own once a second, which is the
    # path that works whether the day was clicked or set.
    screens.tick(user_data)
    harness.check(
        h,
        text_of(ui[].settings_date_caption) == screens.date_caption(user_data, quit_day),
        "the caption names the day the grid is on",
    )
    # Yesterday and tomorrow are named in words, not counted in hours, so the
    # grid landing on either side of today still reads right.
    var back = sys.local_time(now - Int64(86_400))
    pick_day(ui[].settings_calendar, back.year, back.month - Int64(1), back.day)
    screens.tick(user_data)
    harness.check_eq(
        h,
        text_of(ui[].settings_date_caption),
        screens.date_caption(
            user_data, sys.local_midnight(back.year, back.month, back.day)
        ),
        "yesterday is named, not counted in hours",
    )
    var ahead = sys.local_time(now + Int64(86_400))
    pick_day(ui[].settings_calendar, ahead.year, ahead.month - Int64(1), ahead.day)
    screens.tick(user_data)
    harness.check(
        h,
        text_of(ui[].settings_date_caption)
        != screens.date_caption(
            user_data, sys.local_midnight(back.year, back.month, back.day)
        ),
        "the caption follows the day the grid is on",
    )
    _ = pick_day_relative(ui[].settings_calendar, Int64(3))
    screens.tick(user_data)
    press(ui[].settings_save)

    harness.check(
        h, show_page(user_data) == screens.PAGE_DASH, "saving moves on to the dashboard"
    )
    harness.check(
        h, gtk.widget_get_visible(ui[].switcher), "the tabs appear once there is a profile"
    )
    var profile = model_of(user_data)[].profile
    harness.check(h, profile.cigs_per_day == Int64(20), "the daily count is remembered")
    harness.check(
        h, profile.pack_price == Float64(7.5), "the price keeps its cents"
    )
    harness.check(
        h, profile.quit_epoch == quit_day, "the day on the calendar is the day that is stored"
    )
    harness.check(
        h,
        profile.is_planned(sys.now_epoch()) and not profile.quit_started,
        "a day still to come is a plan, and nothing is counted yet",
    )
    harness.check(
        h,
        not gtk.widget_get_visible(ui[].dash_quit_now),
        "the quit button waits for the day it belongs to",
    )
    harness.check(h, profile.is_configured(), "the profile counts as set up")
    harness.check(
        h, text_of(ui[].dash_days).byte_length() > 0, "the dashboard says how long is left"
    )
    harness.check(
        h, text_of(ui[].dash_money).byte_length() > 0, "the dashboard shows the money saved"
    )
    harness.check(
        h,
        text_of(ui[].dash_cigs).byte_length() > 0,
        "the dashboard shows the cigarettes not smoked",
    )
    harness.check(
        h,
        text_of(ui[].dash_since).byte_length() > 0,
        "the dashboard says which day it counts from",
    )
    harness.check(h, text_of(ui[].dash_next).byte_length() > 0, "the next milestone is named")
    var fraction = gtk.progress_bar_get_fraction(ui[].dash_bar)
    harness.check(
        h,
        fraction >= c_double(0.0) and fraction <= c_double(1.0),
        "the progress bar sits between empty and full",
    )
    harness.check(
        h,
        sys.read_file(sys.state_path()).byte_length() > 0,
        "the profile was written to disk",
    )
    # Enter in a box is the button, so the form can be filled and sent without
    # aiming at anything.
    press_key(ui[].settings_cigs)
    harness.check(
        h,
        show_page(user_data) == screens.PAGE_DASH
        and model_of(user_data)[].profile.is_configured(),
        "Enter in a box saves, like the button does",
    )
    harness.check(h, ui[].reset_armed == Int32(0), "a save does not arm the reset")

    # A second visit to the page edits what is stored rather than starting over.
    harness.check_eq(
        h,
        gtk.button_get_label(ui[].settings_save),
        screens.words(user_data).t("common_save"),
        "the button now says it saves a change",
    )
    harness.check_eq(
        h, gtk.entry_get_text(ui[].settings_pack_price), "7.50", "the price reads back with its cents"
    )

    # The day arrives. The window cannot be closed for three days and reopened,
    # so the plan is moved onto today the way the clock would have done it, and
    # the button is then driven the way a person would drive it.
    model_of(user_data)[].profile.quit_epoch = screens.today_midnight()
    model_of(user_data)[].profile.quit_started = False
    screens.tick(user_data)
    harness.check(
        h,
        model_of(user_data)[].profile.is_quit_day(sys.now_epoch()),
        "today is the quit day once it gets here",
    )
    harness.check(
        h, gtk.widget_get_visible(ui[].dash_quit_now), "the quit button is there on the day"
    )
    harness.check(
        h,
        text_of(ui[].dash_days) == screens.words(user_data).t("dash_starts_today"),
        "the headline says the day has come",
    )
    harness.check_eq(
        h,
        gtk.button_get_label(ui[].dash_quit_now),
        screens.words(user_data).t("dash_quit_now"),
        "the button says what it does",
    )
    # The press is stamped inside the handler, so the clock is read on both
    # sides of it and the stored moment has to fall between the two. Reading
    # it only afterwards would make this a race: a second boundary between the
    # stamp and the reading would fail it, and only now and then.
    var pressed_from = sys.now_epoch()
    press(ui[].dash_quit_now)
    var pressed_to = sys.now_epoch()
    harness.check(
        h,
        model_of(user_data)[].profile.quit_started
        and model_of(user_data)[].profile.quit_epoch >= pressed_from
        and model_of(user_data)[].profile.quit_epoch <= pressed_to,
        "the press is the moment the count starts from",
    )
    harness.check(
        h,
        not model_of(user_data)[].profile.is_planned(pressed_to),
        "a press ends the plan",
    )
    harness.check(
        h,
        not gtk.widget_get_visible(ui[].dash_quit_now),
        "the button leaves once the count is running",
    )
    harness.check(
        h,
        model_of(user_data)[].profile.gains(pressed_to).days == Int64(0),
        "the first moment is day zero",
    )
    harness.check(
        h,
        model_of(user_data)[].profile.gains(pressed_to + Int64(2 * 86_400)).days == Int64(2),
        "two days after the press there are two days",
    )
    # The same press, with the keyboard rather than the mouse.
    model_of(user_data)[].profile.quit_epoch = screens.today_midnight()
    model_of(user_data)[].profile.quit_started = False
    screens.tick(user_data)
    press_key(ui[].dash_quit_now)
    harness.check(
        h, model_of(user_data)[].profile.quit_started, "Enter on the button starts the count too"
    )

    # A craving session: start, start again, stop.
    press(ui[].sos_start)
    harness.check(h, ui[].sos_running == Int32(1), "a craving session starts")
    harness.check(
        h, ui[].sos_left == screens.SOS_SECONDS, "the session starts at five minutes"
    )
    press(ui[].sos_start)
    harness.check(h, ui[].sos_running == Int32(1), "starting twice does not stop the clock")
    press(ui[].sos_stop)
    harness.check(h, ui[].sos_running == Int32(0), "a craving session can be stopped")

    press(ui[].journal_craving_button)
    harness.check(h, model_of(user_data)[].entry_count() == Int(1), "a craving can be logged")
    harness.check(
        h, text_of(ui[].journal_count).byte_length() > 0, "the journal says how much it holds"
    )
    press(ui[].journal_slip_button)
    harness.check(h, model_of(user_data)[].entry_count() == Int(2), "a slip can be logged")
    harness.check(
        h, model_of(user_data)[].slip_count() == Int(1), "the slip is counted as a slip"
    )
    harness.check(
        h,
        sys.read_file(sys.state_path()).find("slip") != -1,
        "the journal was written out too",
    )

    # Language: the one toggle on the settings page flips the stored language
    # and the window text with it.
    var before_title = gtk.window_get_title(ui[].window)
    var before_caption = text_of(ui[].settings_date_caption)
    var before_toggle = gtk.check_button_get_label(ui[].settings_lang)
    gtk.check_button_set_active(ui[].settings_lang, True)
    harness.check(
        h,
        model_of(user_data)[].profile.language != LANG_PT,
        "the language toggle flips the language",
    )
    harness.check(
        h, before_title != gtk.window_get_title(ui[].window), "the window title follows"
    )
    harness.check(
        h, before_caption != text_of(ui[].settings_date_caption), "the date caption follows"
    )
    harness.check(
        h, before_toggle != gtk.check_button_get_label(ui[].settings_lang),
        "the toggle offers the other language",
    )
    harness.check(
        h,
        text_of(ui[].settings_cigs_label).byte_length() > 0,
        "the fields keep their captions",
    )
    harness.check(
        h, gtk.button_get_label(ui[].settings_save).byte_length() > 0, "the buttons keep their text"
    )
    harness.check(
        h,
        gtk.button_get_label(ui[].settings_about_button).byte_length() > 0,
        "the about button is named in the new language",
    )

    # The about box: opened from the settings page, named in whichever language
    # is stored, brought forward rather than doubled, and closed again on every
    # gesture a person has, including the titlebar's own close.
    harness.check(h, ui[].about_open == Int32(0), "the about box starts closed")
    press(ui[].settings_about_button)
    harness.check(h, ui[].about_open == Int32(1), "the about button opens the box")
    harness.check(
        h,
        gtk.window_get_title(ui[].about_window) == screens.label(user_data, "about_title"),
        "the about box is named in the chosen language",
    )
    harness.check(
        h, gtk.window_get_title(ui[].about_window) != gtk.window_get_title(ui[].window),
        "the about box is a window of its own",
    )
    var first_about = Int(ui[].about_window)
    press_key(ui[].settings_about_button)
    harness.check(
        h, Int(ui[].about_window) == first_about, "a second press reuses the same box"
    )
    press(ui[].about_close)
    harness.check(h, ui[].about_open == Int32(0), "the close button closes the box")
    press(ui[].settings_about_button)
    harness.check(h, ui[].about_open == Int32(1), "the box opens again afterwards")
    press_key(ui[].about_close)
    harness.check(h, ui[].about_open == Int32(0), "the keyboard closes it as well")
    press(ui[].settings_about_button)
    gtk.window_close(ui[].about_window)
    harness.check(
        h, ui[].about_open == Int32(0), "the titlebar close lets go of the handle"
    )
    harness.check(
        h,
        String(screens.APP_VERSION).byte_length() > 0,
        "the box has a version to show",
    )

    # Reset asks once, then clears and goes back to the settings page. The
    # second press is a keyboard one, so both gestures are covered: a mouse
    # click ends in `clicked` and Enter ends in `activate`, and this GTK keeps
    # the two apart.
    press(ui[].settings_reset)
    harness.check(h, ui[].reset_armed == Int32(1), "the first reset only arms")
    harness.check(
        h, model_of(user_data)[].profile.is_configured(), "nothing is lost while it waits"
    )
    press_key(ui[].settings_reset)
    harness.check(
        h, not model_of(user_data)[].profile.is_configured(), "the second reset starts over"
    )
    harness.check(
        h, show_page(user_data) == screens.PAGE_SETTINGS, "starting over goes back to settings"
    )
    harness.check(
        h, not gtk.widget_get_visible(ui[].switcher), "the tabs go away again"
    )
    harness.check(h, ui[].reset_armed == Int32(0), "the reset button is disarmed afterwards")

    # The saved state is this run's own, so the probe leaves no trace behind.
    _ = sys.remove_file(sys.state_path())
    harness.finish(h)


def main() raises:
    # The app is started exactly as it is in anger, window and loop included, so
    # the checks run against the same code a person would use.
    var model_block = host.take_model()
    host.place_model(model_block, State())
    var ui_block = host.take_ui()
    ui_of(ui_block)[].model_address = Int(model_block)

    var loop = app.startup(ui_block)
    if host.is_null(loop):
        print("not ok - there was no window to check")
        return
    _ = external_call["g_timeout_add", c_uint](SETTLE_MS, on_settled, ui_block, gtk.no_notify())
    gtk.main_loop_run(loop)
    print("the window closed on its own")
