"""What GTK calls when something happens.

Each function here has the shape GTK expects and hands the rest of the work to
`ui.screens`. The connections are written out at the bottom rather than wrapped
up, because a function cannot travel as an ordinary argument in Mojo: the call
GTK wants has to name the callback directly.

The order of the parameters is GTK's, not the app's: a signal callback is
handed the widget it came from first and the app's own pointer second, a timer
callback is handed only the app's pointer, and the drawing callback sits
between them with the size in the middle.
"""

from gtk import gtk
from i18n.strings import LANG_EN, LANG_PT
from lib import sys
from model.state import KIND_CRAVING, KIND_SLIP
from std.ffi import c_double, c_int, c_uint, c_ulong, external_call
from ui import screens
from ui.host import Widget, model_of, ui_of

comptime TICK_MS: c_uint = c_uint(1000)
comptime TAU: c_double = c_double(6.28318)


def start_window(user_data: Widget, loop: Widget) raises:
    """Build the window, connect the buttons and wait for the window to go.

    The loop is handed over rather than created here so that the callback on
    the window's "destroy" can end it: once the window is gone there is
    nothing left to run for.
    """
    screens.build_all(user_data)
    wire(user_data)
    _ = external_call["g_signal_connect_data", c_ulong](
        ui_of(user_data)[].window,
        "destroy".as_c_string_span(),
        on_window_gone,
        loop,
        gtk.no_notify(),
        c_int(0),
    )


@always_inline("nodebug")
def on_window_gone(window: Widget, loop: Widget) abi("C"):
    """The window is closed or destroyed, so the wait is over."""
    gtk.main_loop_quit(loop)


@always_inline("nodebug")
def on_tick(user_data: Widget) abi("C") -> c_int:
    """The window's heartbeat, once a second.

    The work is on the screens side, where the rest of the window's state
    lives; the only thing that has to happen here is saying yes to the next
    tick, since a zero would take the timer off the loop.
    """
    screens.tick(user_data)
    return c_int(1)


@always_inline("nodebug")
def on_sos_start(button: Widget, user_data: Widget) abi("C"):
    var ui = ui_of(user_data)
    if ui[].sos_running != Int32(0):
        return
    ui[].sos_running = Int32(1)
    ui[].sos_left = screens.SOS_SECONDS
    ui[].breathe = Int32(0)
    screens.refresh_sos(user_data)
    gtk.widget_queue_draw(ui[].sos_area)


@always_inline("nodebug")
def on_sos_stop(button: Widget, user_data: Widget) abi("C"):
    var ui = ui_of(user_data)
    ui[].sos_running = Int32(0)
    ui[].sos_left = Int32(0)
    ui[].breathe = Int32(0)
    screens.refresh_sos(user_data)
    gtk.widget_queue_draw(ui[].sos_area)


@always_inline("nodebug")
def on_craving_log(button: Widget, user_data: Widget) abi("C"):
    screens.log_entry(user_data, KIND_CRAVING)


@always_inline("nodebug")
def on_slip_log(button: Widget, user_data: Widget) abi("C"):
    screens.log_entry(user_data, KIND_SLIP)


@always_inline("nodebug")
def on_save_settings(button: Widget, user_data: Widget) abi("C"):
    screens.save_profile(user_data)


@always_inline("nodebug")
def on_quit_now(button: Widget, user_data: Widget) abi("C"):
    """The chosen day has arrived and the count starts from right now."""
    screens.quit_now(user_data)


@always_inline("nodebug")
def on_date_changed(
    calendar: Widget, spec: Widget, user_data: Widget
) abi("C"):
    """The calendar's date property moved, so a day was picked.

    A property change is handed the object and the parameter that describes the
    property, which is why this is a three argument callback. The grid itself
    carries the day, so nothing has to be read out of the arguments.
    """
    screens.refresh_date_caption(user_data)


@always_inline("nodebug")
def on_language(button: Widget, user_data: Widget) abi("C"):
    var model = model_of(user_data)
    var profile = model[].profile
    profile.language = LANG_EN if profile.language == LANG_PT else LANG_PT
    model[].profile = profile
    _ = screens.persist(user_data)
    screens.retitle(user_data)


@always_inline("nodebug")
def on_reset(button: Widget, user_data: Widget) abi("C"):
    var ui = ui_of(user_data)
    if ui[].reset_armed == Int32(0):
        ui[].reset_armed = Int32(1)
        gtk.button_set_label(button, screens.label(user_data, "settings_reset_confirm"))
        return
    var now = sys.now_epoch()
    model_of(user_data)[].start_fresh(now, now)
    _ = screens.persist(user_data)
    ui[].reset_armed = Int32(0)
    gtk.button_set_label(button, screens.label(user_data, "settings_reset"))
    screens.fill_profile(user_data)
    screens.show_setup(user_data)


@always_inline("nodebug")
def on_sos_draw(
    area: Widget, cr: gtk.Cairo, width: c_int, height: c_int, user_data: Widget
) abi("C"):
    var ui = ui_of(user_data)
    var middle = c_double(width) / c_double(2)
    var radius = c_double(height) / c_double(2) * c_double(0.78)
    if ui[].sos_running != Int32(0):
        radius = radius * c_double(screens.breathe_size(ui[].breathe))

    gtk.cairo_set_source_rgba(cr, c_double(0.20), c_double(0.55), c_double(0.85), c_double(0.30))
    gtk.cairo_arc(cr, middle, middle, radius, c_double(0.0), TAU)
    gtk.cairo_fill(cr)
    gtk.cairo_set_source_rgba(cr, c_double(0.30), c_double(0.65), c_double(0.95), c_double(0.95))
    gtk.cairo_set_line_width(cr, c_double(2.0))
    gtk.cairo_arc(cr, middle, middle, radius, c_double(0.0), TAU)
    gtk.cairo_stroke(cr)


def wire(user_data: Widget):
    """Connect every signal the window needs, once the widgets exist.

    The work is spread over a few small functions on purpose: each one names
    its callbacks at the call site, because a function cannot be handed over
    as an ordinary argument in Mojo, and a short function per group keeps each
    of those call sites easy to read.
    """
    wire_craving(user_data)
    wire_journal(user_data)
    wire_dashboard(user_data)
    wire_settings(user_data)


def wire_dashboard(user_data: Widget):
    """The one button that starts the count, wired like every other one."""
    var ui = ui_of(user_data)
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].dash_quit_now, "clicked".as_c_string_span(), on_quit_now, user_data, gtk.no_notify(), c_int(0)
    )
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].dash_quit_now, "activate".as_c_string_span(), on_quit_now, user_data, gtk.no_notify(), c_int(0)
    )


def wire_craving(user_data: Widget):
    var ui = ui_of(user_data)
    # Every button is wired twice, for `clicked` and for `activate`. A press
    # with the mouse ends in `clicked` and Enter or space ends in `activate`,
    # and on this GTK neither one follows the other: activating a button
    # programmatically emits `activate` alone. Listening to one of the two
    # leaves the other gesture dead, and one gesture still reaches the callback
    # once, because one gesture only ever emits one of them.
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].sos_start, "clicked".as_c_string_span(), on_sos_start, user_data, gtk.no_notify(), c_int(0)
    )
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].sos_start, "activate".as_c_string_span(), on_sos_start, user_data, gtk.no_notify(), c_int(0)
    )
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].sos_stop, "clicked".as_c_string_span(), on_sos_stop, user_data, gtk.no_notify(), c_int(0)
    )
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].sos_stop, "activate".as_c_string_span(), on_sos_stop, user_data, gtk.no_notify(), c_int(0)
    )


def wire_journal(user_data: Widget):
    var ui = ui_of(user_data)
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].journal_craving_button,
        "clicked".as_c_string_span(),
        on_craving_log,
        user_data,
        gtk.no_notify(),
        c_int(0),
    )
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].journal_craving_button,
        "activate".as_c_string_span(),
        on_craving_log,
        user_data,
        gtk.no_notify(),
        c_int(0),
    )
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].journal_slip_button, "clicked".as_c_string_span(), on_slip_log, user_data, gtk.no_notify(), c_int(0)
    )
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].journal_slip_button, "activate".as_c_string_span(), on_slip_log, user_data, gtk.no_notify(), c_int(0)
    )


def wire_settings(user_data: Widget):
    """The settings page, the craving drawing and the tick."""
    var ui = ui_of(user_data)
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].settings_save, "clicked".as_c_string_span(), on_save_settings, user_data, gtk.no_notify(), c_int(0)
    )
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].settings_save, "activate".as_c_string_span(), on_save_settings, user_data, gtk.no_notify(), c_int(0)
    )
    # Enter in any of the three boxes is the same as pressing the button, which
    # is how a form behaves and a way to save that does not depend on aiming at
    # the button.
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].settings_cigs, "activate".as_c_string_span(), on_save_settings, user_data, gtk.no_notify(), c_int(0)
    )
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].settings_pack_size, "activate".as_c_string_span(), on_save_settings, user_data, gtk.no_notify(), c_int(0)
    )
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].settings_pack_price, "activate".as_c_string_span(), on_save_settings, user_data, gtk.no_notify(), c_int(0)
    )
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].settings_calendar,
        "notify::date".as_c_string_span(),
        on_date_changed,
        user_data,
        gtk.no_notify(),
        c_int(0),
    )
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].settings_lang, "toggled".as_c_string_span(), on_language, user_data, gtk.no_notify(), c_int(0)
    )
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].settings_reset, "clicked".as_c_string_span(), on_reset, user_data, gtk.no_notify(), c_int(0)
    )
    _ = external_call["g_signal_connect_data", c_ulong](
        ui[].settings_reset, "activate".as_c_string_span(), on_reset, user_data, gtk.no_notify(), c_int(0)
    )
    _ = external_call["gtk_drawing_area_set_draw_func", NoneType](
        ui[].sos_area, on_sos_draw, user_data, gtk.no_notify()
    )
    # One tick for the whole window: it refreshes the dashboard every second
    # and drives the craving countdown while one is running.
    _ = external_call["g_timeout_add", c_uint](TICK_MS, on_tick, user_data, gtk.no_notify())
