# Copyright (C) 2026 Luís Louro
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Licensed under the GNU General Public License, version 3 or later. The full
# text is in LICENSE.

"""Starting smokenot up.

The window and its screens live in `ui.screens`, the callbacks in
`ui.handlers`, and this file ties them together: it loads the saved state,
parks it somewhere the callbacks can reach, starts GTK, and then waits on a
main loop until the window is closed.

The wait is a plain GLib loop rather than a `GtkApplication`. An application
wants a name on the session bus, and a strict snap's AppArmor policy only lets
a snap own a name that was asked for by hand, which is one more thing that can
be refused on a packaged build. A window on a loop of our own needs nothing
from the bus at all.
"""

from gtk import gtk
from lib import sys
from model.state import load
from std.ffi import c_int
from ui import handlers, host
from ui.host import Widget, ui_of


def startup(user_data: Widget) raises -> Widget:
    """Start GTK, put the window on screen, and hand back the loop to wait on.

    A pointer that is null comes back when GTK would not start, which in
    practice means there is no display to draw on.
    """
    if not gtk.init():
        print("GTK would not start, so there is no window to show")
        return Widget(unsafe_from_address=Int(0))
    var loop = gtk.main_loop_new(False)
    handlers.start_window(user_data, loop)
    return loop


def run() raises -> c_int:
    """Show the window and wait until it closes."""
    var model = load(sys.state_path())
    var model_block = host.take_model()
    host.place_model(model_block, model)
    var ui_block = host.take_ui()
    ui_of(ui_block)[].model_address = Int(model_block)

    var loop = startup(ui_block)
    if host.is_null(loop):
        gtk.release(model_block)
        gtk.release(ui_block)
        return c_int(1)
    gtk.main_loop_run(loop)
    gtk.release(model_block)
    gtk.release(ui_block)
    return c_int(0)
