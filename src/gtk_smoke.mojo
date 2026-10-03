# Copyright (C) 2026 Luís Louro
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Licensed under the GNU General Public License, version 3 or later. The full
# text is in LICENSE.

# Smoke test for the wrapper layer: build a window with the widgets the app
# needs, prove the signal thunk still round-trips state, then quit.
from gtk import gtk
from std.ffi import c_double, c_int, c_uint, c_ulong, external_call
from std.sys import size_of


comptime Widget = gtk.Widget
comptime AppId = "com.smokenot.smoke"


struct Smoke(TrivialRegisterPassable, ImplicitlyCopyable):
    var clicks: Int32
    var app: Widget
    var win: Widget
    var counter: Widget
    var area: Widget


def _alloc() raises -> gtk.Widget:
    return gtk.alloc(size_of[Smoke]())


@always_inline("nodebug")
def on_clicked(button: Widget, user_data: Widget) abi("C"):
    var sp = gtk.state_of[Smoke](user_data)
    var st = sp[]
    st.clicks += Int32(1)
    sp[] = st
    gtk.label_set_text(st.counter, String("clicks = ") + String(st.clicks))
    gtk.progress_bar_set_fraction(st.area, c_double(0.5))


@always_inline("nodebug")
def on_draw(
    area: Widget, cr: gtk.Cairo, width: c_int, height: c_int, user_data: Widget
) abi("C"):
    gtk.cairo_set_source_rgba(cr, c_double(0.2), c_double(0.6), c_double(0.9), c_double(1.0))
    gtk.cairo_arc(cr, c_double(width) / c_double(2), c_double(height) / c_double(2), c_double(20), c_double(0), c_double(6.28))
    gtk.cairo_fill(cr)


@always_inline("nodebug")
def on_quit_later(user_data: Widget) abi("C") -> c_int:
    var st = gtk.state_of[Smoke](user_data)[]
    gtk.application_quit(st.app)
    return c_int(0)


@always_inline("nodebug")
def on_activate(app: Widget, user_data: Widget) abi("C"):
    var sp = gtk.state_of[Smoke](user_data)
    var st = sp[]
    st.app = app

    var win = gtk.window_new(app)
    gtk.window_set_title(win, "smokenot gtk smoke")
    gtk.window_set_default_size(win, c_int(420), c_int(240))

    var bar = gtk.progress_bar_new()
    gtk.progress_bar_set_show_text(bar, True)
    gtk.progress_bar_set_text(bar, "0%")
    st.area = bar

    var stack = gtk.stack_new()
    var page = gtk.box_new(gtk.ORIENTATION_VERTICAL, c_int(8))
    var heading = gtk.label_new_literal("GTK wrappers work")
    gtk.widget_add_css_class(heading, "title-1")
    var counter = gtk.label_new_literal("clicks = 0")
    var entry = gtk.entry_new()
    gtk.entry_set_placeholder(entry, "note")
    var button = gtk.button_new_literal("click me")
    _ = external_call["g_signal_connect_data", c_ulong](
        button, "clicked".as_c_string_span(), on_clicked, user_data, None, c_int(0)
    )
    var area = gtk.drawing_area_new()
    gtk.drawing_area_set_size(area, c_int(120), c_int(120))
    external_call["gtk_drawing_area_set_draw_func", NoneType](area, on_draw, user_data, None)
    gtk.box_append(page, heading)
    gtk.box_append(page, counter)
    gtk.box_append(page, entry)
    gtk.box_append(page, button)
    gtk.box_append(page, area)
    gtk.stack_add_titled(stack, page, String("page"), String("Page"))
    st.counter = counter
    st.win = win
    sp[] = st

    var outer = gtk.box_new(gtk.ORIENTATION_VERTICAL, c_int(0))
    var switcher = gtk.stack_switcher_new()
    gtk.box_append(outer, switcher)
    gtk.box_append(outer, stack)
    gtk.box_append(outer, bar)
    gtk.window_set_child(win, outer)
    gtk.window_present(win)

    # Prove the click path works without a person having to click.
    _ = external_call["g_signal_emit_by_name", c_ulong](
        button, "clicked".as_c_string_span(), None
    )
    var after = gtk.state_of[Smoke](user_data)[]
    print("clicks after emitting the signal:", after.clicks)
    print("counter label:", gtk.label_get_text(counter))
    print("title:", gtk.window_get_title(win))
    print("entry text:", gtk.entry_get_text(entry))
    print("visible child:", gtk.stack_get_visible_child(stack))
    _ = external_call["g_timeout_add", c_uint](c_uint(1200), on_quit_later, user_data)


def main() raises:
    var app = gtk.application_new(String(AppId), c_int(0))
    var data = _alloc()
    _ = external_call["g_signal_connect_data", c_ulong](
        app, "activate".as_c_string_span(), on_activate, data, None, c_int(0)
    )
    var rc = gtk.application_run(app, c_int(0), Optional[gtk.ArgvPtr]())
    var st = gtk.state_of[Smoke](data)[]
    print("run returned", rc)
    print("clicks:", st.clicks)
    print("title after run:", gtk.window_get_title(st.win))
    gtk.release(data)
