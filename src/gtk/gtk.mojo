"""Typed wrappers over the GTK4 C API.

The interface code never calls `external_call` itself: every GTK function is
wrapped here once, so the rest of the app is written in Mojo with names and
signatures that say what they mean.

Two things about the FFI shape are worth knowing before changing this file.

A function reference cannot be passed as an argument, so anything that takes a
callback cannot be wrapped: Mojo builds the C thunk at the `external_call` site
and needs the callback written there. `g_signal_connect_data`,
`gtk_drawing_area_set_draw_func` and `g_timeout_add` are therefore called from
the interface code next to the callbacks they wire up, and every connection in a
module must have the same callback shape, because a repeated `external_call`
symbol has to lower to the same signature twice.

GTK4 has to be initialised before any widget is built. `gtk_application_new`
plus `g_application_run` does that as part of starting the loop, so widgets are
only ever created from inside an activated callback, never from `main`.

Nothing here raises except `alloc`, which is only called before the loop
starts. GTK callbacks cannot propagate an error, and a constructor that
returned nothing would have to be handled anyway, so the constructors hand
back the pointer GTK gave them. Every one of these constructors aborts inside
GTK if it cannot allocate, so an unusable pointer here means the wrong
function was called rather than a runtime condition to recover from.
"""

from std.ffi import (
    c_char,
    c_double,
    c_float,
    c_int,
    c_long,
    c_size_t,
    c_uint,
    c_ulong,
    external_call,
)
from std.sys import size_of
from lib.text import c_string_to_string

# GTK hands out opaque pointers. Keeping them as raw pointers means no wrapper
# ever has to guess at a layout, and an empty pointer reads as "nothing".
comptime Widget = Pointer[UInt8, MutUntrackedOrigin]
comptime Cairo = Pointer[UInt8, MutUntrackedOrigin]
comptime CStrPtr = Pointer[c_char, MutUntrackedOrigin]
comptime ArgvPtr = Pointer[CStrPtr, MutUntrackedOrigin]
comptime StackPage = Pointer[UInt8, MutUntrackedOrigin]

comptime ORIENTATION_HORIZONTAL: c_int = 0
comptime ORIENTATION_VERTICAL: c_int = 1
comptime ALIGN_FILL: c_int = 0
comptime ALIGN_START: c_int = 1
comptime ALIGN_END: c_int = 2
comptime ALIGN_CENTER: c_int = 3

comptime POLICY_ALWAYS: c_uint = 0
comptime POLICY_AUTOMATIC: c_uint = 1
comptime POLICY_NEVER: c_uint = 2
comptime POLICY_EXTERNAL: c_uint = 3


# --------------------------------------------------------------- pointers


def _as_string(raw: Optional[CStrPtr]) -> String:
    """C string to Mojo string, or an empty one when there is nothing there."""
    if raw:
        try:
            return c_string_to_string(Int(raw.value()))
        except:
            return String("")
    return String("")


def _taken(maybe: Optional[Widget]) -> Widget:
    """The pointer GTK returned, or a dangling one if there was none."""
    if maybe:
        return maybe.value()
    return Pointer[UInt8, MutUntrackedOrigin].unsafe_dangling()


def alloc(size: Int) raises -> Widget:
    """Zeroed C memory, for the state GTK passes back through `user_data`."""
    var raw = external_call[
        "malloc", Optional[Widget]
    ](c_size_t(size))
    if not raw:
        raise Error("out of memory")
    var block = raw.value()
    _ = external_call["memset", Widget](block, c_int(0), c_size_t(size))
    return block


def state_of[T: AnyType](block: Widget) -> Pointer[T, MutUntrackedOrigin]:
    """Typed view of C memory that holds one `T`.

    GTK hands state back as an untyped pointer, so this is how a callback
    gets at it again. The caller owns the memory.

    A callback reads and writes through the pointer it returns, `sp[]` for the
    value and `sp[] = value` to put one back, because a generic function cannot
    hand a value of an unknown type back to its caller.
    """
    return Pointer[T, MutUntrackedOrigin](unsafe_from_address=Int(block))


def release(block: Widget):
    external_call["free", NoneType](block)


# -------------------------------------------------------------- lifetime


# Starting a timer takes a callback too, so it is not wrapped either. Call
# `external_call["g_timeout_add", c_uint](interval, callback, user_data)` and keep
# the returned id to hand to `source_remove` when the timer is no longer wanted.

def source_remove(tag: c_uint) -> Bool:
    return external_call["g_source_remove", c_int](tag) != c_int(0)


# ---------------------------------------------------------------- the loop


def no_notify() -> Pointer[Widget, MutUntrackedOrigin]:
    """An explicit null pointer for a callback slot GTK should leave empty.

    Mojo's `None` is a value, not an address, and GTK would go on to call
    whatever it is handed when the connection is dropped, so a real null
    pointer is passed instead.
    """
    return Pointer[Widget, MutUntrackedOrigin](unsafe_from_address=Int(0))


def init() -> Bool:
    """Start GTK ahead of the main loop, for code that builds widgets first.

    The arguments are passed as null on purpose: this says "there are no
    command line arguments to hand back", which is what the app means too.
    """
    var none_int: Optional[Pointer[c_int, MutUntrackedOrigin]] = None
    var none_argv: Optional[Pointer[ArgvPtr, MutUntrackedOrigin]] = None
    var ready = external_call["gtk_init_check", c_int](
        none_int, none_argv
    )
    return ready != c_int(0)


# The app waits on a loop of its own rather than on GApplication. A
# GtkApplication wants a name on the session bus, and a strict snap's AppArmor
# policy only lets a snap own a name the dbus interface asked for by hand, so a
# plain window is both simpler and one less thing to be refused.
def main_loop_new(is_running: Bool) -> Widget:
    var running = c_int(0)
    if is_running:
        running = c_int(1)
    return _taken(external_call["g_main_loop_new", Optional[Widget]](running))


def main_loop_run(loop: Widget):
    external_call["g_main_loop_run", NoneType](loop)


def main_loop_quit(loop: Widget):
    external_call["g_main_loop_quit", NoneType](loop)


# ---------------------------------------------------------------- window


def window_new() -> Widget:
    return _taken(external_call["gtk_window_new", Optional[Widget]]())



def window_present(win: Widget):
    external_call["gtk_window_present", NoneType](win)


def window_close(win: Widget):
    external_call["gtk_window_close", NoneType](win)


def window_set_title(win: Widget, title: String):
    var text = title
    external_call["gtk_window_set_title", NoneType](win, text.as_c_string_span())


def window_set_title_literal(win: Widget, title: StringLiteral):
    external_call["gtk_window_set_title", NoneType](win, title.as_c_string_span())


def window_get_title(win: Widget) -> String:
    var raw = external_call["gtk_window_get_title", Optional[CStrPtr]](win)
    return _as_string(raw)


def window_set_default_size(win: Widget, width: c_int, height: c_int):
    external_call["gtk_window_set_default_size", NoneType](win, width, height)


def window_set_resizable(win: Widget, resizable: Bool):
    external_call["gtk_window_set_resizable", NoneType](
        win, c_int(1 if resizable else 0)
    )


def window_set_modal(win: Widget, modal: Bool):
    external_call["gtk_window_set_modal", NoneType](win, c_int(1 if modal else 0))


def window_set_transient_for(win: Widget, parent: Widget):
    external_call["gtk_window_set_transient_for", NoneType](win, parent)


def window_set_hide_on_close(win: Widget, hide: Bool):
    external_call["gtk_window_set_hide_on_close", NoneType](win, c_int(1 if hide else 0))


def window_set_child(win: Widget, child: Widget):
    external_call["gtk_window_set_child", NoneType](win, child)


def window_set_default_widget(win: Widget, widget: Widget):
    external_call["gtk_window_set_default_widget", NoneType](win, widget)


# ------------------------------------------------------------ containers


def box_new(orientation: c_int, spacing: c_int) -> Widget:
    var box = external_call[
        "gtk_box_new", Optional[Widget]
    ](orientation, spacing)
    return _taken(box)


def box_append(box: Widget, child: Widget):
    external_call["gtk_box_append", NoneType](box, child)


def box_prepend(box: Widget, child: Widget):
    external_call["gtk_box_prepend", NoneType](box, child)


def box_remove(box: Widget, child: Widget):
    external_call["gtk_box_remove", NoneType](box, child)


def box_set_spacing(box: Widget, spacing: c_int):
    external_call["gtk_box_set_spacing", NoneType](box, spacing)


def stack_new() -> Widget:
    var stack = external_call[
        "gtk_stack_new", Optional[Widget]
    ]()
    return _taken(stack)


def stack_add_named(stack: Widget, child: Widget, name: String):
    var label = name
    external_call["gtk_stack_add_named", NoneType](stack, child, label.as_c_string_span())


def stack_add_titled(stack: Widget, child: Widget, name: String, title: String):
    var key = name
    var heading = title
    external_call["gtk_stack_add_titled", NoneType](
        stack, child, key.as_c_string_span(), heading.as_c_string_span()
    )


def stack_set_visible_child(stack: Widget, name: String):
    var key = name
    external_call["gtk_stack_set_visible_child_name", NoneType](
        stack, key.as_c_string_span()
    )


def stack_get_visible_child(stack: Widget) -> String:
    var raw = external_call[
        "gtk_stack_get_visible_child_name", Optional[CStrPtr]
    ](stack)
    return _as_string(raw)


def stack_switcher_set_stack(switcher: Widget, stack: Widget):
    external_call["gtk_stack_switcher_set_stack", NoneType](switcher, stack)


def stack_set_title(stack: Widget, name: String, title: String):
    """Retitle one page of a stack.

    GTK4 has no `gtk_stack_set_title`: the title lives on the page, which is
    looked up by the name the page was added under.
    """
    var child = name
    var text = title
    var found_child = external_call[
        "gtk_stack_get_child_by_name", Optional[Widget]
    ](stack, child.as_c_string_span())
    if not found_child:
        return
    var page = external_call[
        "gtk_stack_get_page", Optional[StackPage]
    ](stack, found_child.value())
    if page:
        external_call["gtk_stack_page_set_title", NoneType](
            page.value(), text.as_c_string_span()
        )


def stack_set_transition(stack: Widget, kind: c_int):
    external_call["gtk_stack_set_transition", NoneType](stack, kind)


def stack_switcher_new() -> Widget:
    var switcher = external_call[
        "gtk_stack_switcher_new", Optional[Widget]
    ]()
    return _taken(switcher)


def scrolled_window_new(expand_horizontal: Bool, expand_vertical: Bool) -> Widget:
    """A scrolling area. GTK asks for expansion flags here, not sizes."""
    var scroll = external_call[
        "gtk_scrolled_window_new", Optional[Widget]
    ](c_int(1) if expand_horizontal else c_int(0), c_int(1) if expand_vertical else c_int(0))
    var view = _taken(scroll)
    external_call["gtk_scrolled_window_set_policy", NoneType](
        view, POLICY_NEVER, POLICY_AUTOMATIC
    )
    return view


def scrolled_window_set_child(scroll: Widget, child: Widget):
    external_call["gtk_scrolled_window_set_child", NoneType](scroll, child)


def notebook_new() -> Widget:
    var book = external_call[
        "gtk_notebook_new", Optional[Widget]
    ]()
    return _taken(book)


def list_box_new() -> Widget:
    var list = external_call[
        "gtk_list_box_new", Optional[Widget]
    ]()
    return _taken(list)


def list_box_append(list: Widget, child: Widget):
    external_call["gtk_list_box_append", NoneType](list, child)


def list_box_set_selection_mode_none(list: Widget):
    external_call["gtk_list_box_set_selection_mode", NoneType](list, c_int(0))


# ---------------------------------------------------------------- labels


def label_new(text: String) -> Widget:
    var copy = text
    var label = external_call["gtk_label_new", Optional[Widget]](
        copy.as_c_string_span()
    )
    return _taken(label)


def label_new_literal(text: StringLiteral) -> Widget:
    var label = external_call[
        "gtk_label_new", Optional[Widget]
    ](text.as_c_string_span())
    return _taken(label)


def label_set_text(label: Widget, text: String):
    var copy = text
    external_call["gtk_label_set_text", NoneType](label, copy.as_c_string_span())


def label_set_text_literal(label: Widget, text: StringLiteral):
    external_call["gtk_label_set_text", NoneType](label, text.as_c_string_span())


def label_get_text(label: Widget) -> String:
    var raw = external_call["gtk_label_get_text", Optional[CStrPtr]](label)
    return _as_string(raw)


def label_set_wrap(label: Widget, wrap: Bool):
    external_call["gtk_label_set_wrap", NoneType](label, c_int(1 if wrap else 0))


def label_set_wrap_mode(label: Widget, mode: c_int):
    external_call["gtk_label_set_wrap_mode", NoneType](label, c_int(mode))


def label_set_justify(label: Widget, justify: c_int):
    external_call["gtk_label_set_justify", NoneType](label, justify)


def label_set_selectable(label: Widget, selectable: Bool):
    external_call["gtk_label_set_selectable", NoneType](
        label, c_int(1 if selectable else 0)
    )


def label_set_xalign(label: Widget, xalign: c_float):
    # GTK's alignment properties are single precision, so this takes a c_float
    # rather than a c_double: handing over a double reads the wrong bits.
    external_call["gtk_label_set_xalign", NoneType](label, xalign)


def label_set_lines(label: Widget, lines: c_int):
    external_call["gtk_label_set_lines", NoneType](label, lines)


# --------------------------------------------------------------- buttons


def button_new(label: String) -> Widget:
    var copy = label
    var button = external_call["gtk_button_new_with_label", Optional[Widget]](
        copy.as_c_string_span()
    )
    return _taken(button)


def button_new_literal(label: StringLiteral) -> Widget:
    var button = external_call[
        "gtk_button_new_with_label", Optional[Widget]
    ](label.as_c_string_span())
    return _taken(button)


def button_set_label(button: Widget, label: String):
    var copy = label
    external_call["gtk_button_set_label", NoneType](button, copy.as_c_string_span())


def check_button_new(label: String) -> Widget:
    var copy = label
    var button = external_call[
        "gtk_check_button_new_with_label", Optional[Widget]
    ](copy.as_c_string_span())
    return _taken(button)


def check_button_get_active(button: Widget) -> Bool:
    return external_call["gtk_check_button_get_active", c_int](button) != c_int(0)


def widget_activate(widget: Widget) -> Bool:
    """Fire a widget's activate signal, which is what a click on it does."""
    return external_call["gtk_widget_activate", Bool](widget) == True


def button_get_label(button: Widget) -> String:
    var raw = external_call["gtk_button_get_label", Optional[CStrPtr]](button)
    return _as_string(raw)


def check_button_set_active(button: Widget, active: Bool):
    external_call["gtk_check_button_set_active", NoneType](
        button, c_int(1 if active else 0)
    )


def check_button_set_label(button: Widget, label: String):
    var copy = label
    external_call["gtk_check_button_set_label", NoneType](
        button, copy.as_c_string_span()
    )


def check_button_get_label(button: Widget) -> String:
    # A check button is not a button here, so its label is its own getter and
    # not the one `GtkButton` would answer to.
    var raw = external_call[
        "gtk_check_button_get_label", Optional[CStrPtr]
    ](button)
    return _as_string(raw)


# ----------------------------------------------------------------- entry


def entry_new() -> Widget:
    var entry = external_call[
        "gtk_entry_new", Optional[Widget]
    ]()
    return _taken(entry)


def entry_set_text(entry: Widget, text: String):
    var copy = text
    external_call["gtk_editable_set_text", NoneType](entry, copy.as_c_string_span())


def entry_get_text(entry: Widget) -> String:
    var raw = external_call["gtk_editable_get_text", Optional[CStrPtr]](entry)
    return _as_string(raw)


def entry_set_placeholder(entry: Widget, text: String):
    var copy = text
    external_call["gtk_entry_set_placeholder_text", NoneType](
        entry, copy.as_c_string_span()
    )


def entry_set_alignment(entry: Widget, align: c_float):
    # The editable's alignment is a single-precision property, not an enum.
    external_call["gtk_editable_set_alignment", NoneType](entry, align)


def entry_set_max_length(entry: Widget, length: c_int):
    external_call["gtk_editable_set_max_width_chars", NoneType](entry, length)


def entry_set_input_purpose(entry: Widget, purpose: c_int):
    external_call["gtk_entry_set_input_purpose", NoneType](entry, purpose)


# ----------------------------------------------------------------- calendar


def calendar_new() -> Widget:
    """The month grid a date is picked on.

    This GTK has no `GtkDateChooser`, so the calendar is the whole picker and
    it sits in the settings page itself rather than behind a popover. It also
    has no `day-selected` signal: the date arrives as the widget's `date`
    property changing, which is what the app listens to.
    """
    var calendar = external_call["gtk_calendar_new", Optional[Widget]]()
    return _taken(calendar)


def calendar_select(calendar: Widget, year: Int64, month: Int64, day: Int64):
    """Point the grid at a day, as if the user had clicked it.

    The month is zero based, the way `GDateTime` and `struct tm` count it, the
    day is one based, and the year is the whole year. The day is pulled back to
    the first of the month before the month and the year move, because GTK
    refuses a combination that is not a real date: the 29th of February set
    straight to 2023 would be rejected with the day's own value in place.
    """
    external_call["gtk_calendar_set_day", NoneType](calendar, c_uint(1))
    external_call["gtk_calendar_set_month", NoneType](calendar, c_uint(month))
    external_call["gtk_calendar_set_year", NoneType](calendar, c_uint(year))
    external_call["gtk_calendar_set_day", NoneType](calendar, c_uint(day))


def calendar_get_date(calendar: Widget) -> Tuple[Int64, Int64, Int64]:
    """The shown year, month and day of the month, the month zero based.

    This GTK's calendar hands the date back as a `GDateTime` with a reference
    of its own, so it is read and dropped here rather than kept, and the month
    is counted from zero to match what `calendar_select` takes.
    """
    var stamp = external_call["gtk_calendar_get_date", Optional[Widget]](calendar)
    if not stamp:
        return (Int64(0), Int64(0), Int64(0))
    var when = stamp.value()
    var year = external_call["g_date_time_get_year", c_int](when)
    var month = external_call["g_date_time_get_month", c_int](when)
    var day = external_call["g_date_time_get_day_of_month", c_int](when)
    _ = external_call["g_date_time_unref", NoneType](when)
    return (Int64(year), Int64(month) - Int64(1), Int64(day))


def calendar_set_heading(calendar: Widget, show: Bool):
    external_call["gtk_calendar_set_show_heading", NoneType](
        calendar, c_int(1 if show else 0)
    )


def calendar_set_day_names(calendar: Widget, show: Bool):
    external_call["gtk_calendar_set_show_day_names", NoneType](
        calendar, c_int(1 if show else 0)
    )


def calendar_set_week_numbers(calendar: Widget, show: Bool):
    external_call["gtk_calendar_set_show_week_numbers", NoneType](
        calendar, c_int(1 if show else 0)
    )


# -------------------------------------------------------------- progress


def progress_bar_new() -> Widget:
    var bar = external_call[
        "gtk_progress_bar_new", Optional[Widget]
    ]()
    return _taken(bar)


def progress_bar_set_fraction(bar: Widget, fraction: c_double):
    external_call["gtk_progress_bar_set_fraction", NoneType](bar, fraction)


def progress_bar_get_fraction(bar: Widget) -> c_double:
    return external_call["gtk_progress_bar_get_fraction", c_double](bar)


def progress_bar_set_text(bar: Widget, text: String):
    var copy = text
    external_call["gtk_progress_bar_set_text", NoneType](bar, copy.as_c_string_span())


def progress_bar_set_show_text(bar: Widget, show: Bool):
    external_call["gtk_progress_bar_set_show_text", NoneType](bar, c_int(1 if show else 0))


def progress_bar_pulse(bar: Widget):
    external_call["gtk_progress_bar_pulse", NoneType](bar)


# -------------------------------------------------------------- drawing


def drawing_area_new() -> Widget:
    var area = external_call[
        "gtk_drawing_area_new", Optional[Widget]
    ]()
    return _taken(area)


def drawing_area_set_size(area: Widget, width: c_int, height: c_int):
    external_call["gtk_drawing_area_set_content_width", NoneType](area, width)
    external_call["gtk_drawing_area_set_content_height", NoneType](area, height)


# -------------------------------------------------------------- spinner


def spinner_new() -> Widget:
    var spinner = external_call[
        "gtk_spinner_new", Optional[Widget]
    ]()
    return _taken(spinner)


def spinner_start(spinner: Widget):
    external_call["gtk_spinner_start", NoneType](spinner)


def spinner_stop(spinner: Widget):
    external_call["gtk_spinner_stop", NoneType](spinner)


# ------------------------------------------------------------- separator


def separator_new(orientation: c_int) -> Widget:
    var rule = external_call[
        "gtk_separator_new", Optional[Widget]
    ](orientation)
    return _taken(rule)


# ------------------------------------------------------------- properties


def widget_set_size_request(widget: Widget, width: c_int, height: c_int):
    external_call["gtk_widget_set_size_request", NoneType](widget, width, height)


def widget_add_css_class(widget: Widget, name: String):
    var copy = name
    external_call["gtk_widget_add_css_class", NoneType](widget, copy.as_c_string_span())


def widget_remove_css_class(widget: Widget, name: String):
    var copy = name
    external_call["gtk_widget_remove_css_class", NoneType](widget, copy.as_c_string_span())


def widget_has_css_class(widget: Widget, name: String) -> Bool:
    var copy = name
    return (
        external_call["gtk_widget_has_css_class", c_int](widget, copy.as_c_string_span())
        != c_int(0)
    )


def widget_set_tooltip(widget: Widget, text: String):
    var copy = text
    external_call["gtk_widget_set_tooltip_text", NoneType](widget, copy.as_c_string_span())


def widget_set_sensitive(widget: Widget, sensitive: Bool):
    external_call["gtk_widget_set_sensitive", NoneType](widget, c_int(1 if sensitive else 0))


def widget_set_visible(widget: Widget, visible: Bool):
    external_call["gtk_widget_set_visible", NoneType](widget, c_int(1 if visible else 0))


def widget_get_visible(widget: Widget) -> Bool:
    return external_call["gtk_widget_get_visible", c_int](widget) != c_int(0)


def widget_set_halign(widget: Widget, align: c_int):
    external_call["gtk_widget_set_halign", NoneType](widget, align)


def widget_set_valign(widget: Widget, align: c_int):
    external_call["gtk_widget_set_valign", NoneType](widget, align)


def widget_set_hexpand(widget: Widget, expand: Bool):
    external_call["gtk_widget_set_hexpand", NoneType](widget, c_int(1 if expand else 0))


def widget_set_vexpand(widget: Widget, expand: Bool):
    external_call["gtk_widget_set_vexpand", NoneType](widget, c_int(1 if expand else 0))


def widget_set_margin_top(widget: Widget, margin: c_int):
    external_call["gtk_widget_set_margin_top", NoneType](widget, margin)


def widget_set_margin_bottom(widget: Widget, margin: c_int):
    external_call["gtk_widget_set_margin_bottom", NoneType](widget, margin)


def widget_set_margin_start(widget: Widget, margin: c_int):
    external_call["gtk_widget_set_margin_start", NoneType](widget, margin)


def widget_set_margin_end(widget: Widget, margin: c_int):
    external_call["gtk_widget_set_margin_end", NoneType](widget, margin)


def widget_set_margins(widget: Widget, margin: c_int):
    widget_set_margin_top(widget, margin)
    widget_set_margin_bottom(widget, margin)
    widget_set_margin_start(widget, margin)
    widget_set_margin_end(widget, margin)


def widget_set_opacity(widget: Widget, opacity: c_int):
    external_call["gtk_widget_set_opacity", NoneType](widget, opacity)


def widget_queue_draw(widget: Widget):
    external_call["gtk_widget_queue_draw", NoneType](widget)


def widget_queue_resize(widget: Widget):
    external_call["gtk_widget_queue_resize", NoneType](widget)


def widget_get_allocated_width(widget: Widget) -> c_int:
    return external_call["gtk_widget_get_allocated_width", c_int](widget)


def widget_get_allocated_height(widget: Widget) -> c_int:
    return external_call["gtk_widget_get_allocated_height", c_int](widget)


def widget_get_parent(widget: Widget) -> Widget:
    return external_call["gtk_widget_get_parent", Widget](widget)


def widget_set_name(widget: Widget, name: String):
    var copy = name
    external_call["gtk_widget_set_name", NoneType](widget, copy.as_c_string_span())


def widget_get_first_child(widget: Widget) -> Widget:
    """The first child in the widget tree, or nothing when there is none.

    A container has no "how many children" call, so walking the list this way
    is how a box gets emptied before it is filled again.
    """
    return external_call["gtk_widget_get_first_child", Widget](widget)


def widget_get_next_sibling(widget: Widget) -> Widget:
    return external_call["gtk_widget_get_next_sibling", Widget](widget)


def label_set_markup(label: Widget, markup: String):
    var copy = markup
    external_call["gtk_label_set_markup", NoneType](label, copy.as_c_string_span())


def label_set_hexpand(label: Widget, expand: Bool):
    external_call["gtk_widget_set_hexpand", NoneType](label, c_int(1) if expand else c_int(0))


def label_set_ellipsize(label: Widget, mode: c_int):
    external_call["gtk_label_set_ellipsize", NoneType](label, mode)


def entry_set_width_chars(entry: Widget, chars: c_int):
    # An entry is an editable, and it is the editable that knows its width.
    external_call["gtk_editable_set_width_chars", NoneType](entry, chars)


# ----------------------------------------------------------------- styling


def style_add_provider(widget: Widget, provider: Widget, priority: c_uint):
    """Install a CSS provider on the display `widget` is on.

    GTK4 has one style context per display rather than per screen, and a
    provider has to reach that one to affect every window.
    """
    external_call["gtk_style_context_add_provider_for_display", NoneType](
        external_call["gtk_widget_get_display", Widget](widget), provider, priority
    )


def css_provider_new() -> Widget:
    return external_call["gtk_css_provider_new", Widget]()


def css_provider_load_from_string(provider: Widget, data: String):
    var copy = data
    _ = external_call["gtk_css_provider_load_from_string", c_int](
        provider,
        copy.as_c_string_span(),
        c_size_t(copy.byte_length()),
        no_notify(),
    )


# ----------------------------------------------------------------- cairo


def cairo_set_source_rgba(cr: Cairo, r: c_double, g: c_double, b: c_double, a: c_double):
    external_call["cairo_set_source_rgba", NoneType](cr, r, g, b, a)


def cairo_set_line_width(cr: Cairo, width: c_double):
    external_call["cairo_set_line_width", NoneType](cr, width)


def cairo_arc(cr: Cairo, x: c_double, y: c_double, radius: c_double, start: c_double, end: c_double):
    external_call["cairo_arc", NoneType](cr, x, y, radius, start, end)


def cairo_rectangle(cr: Cairo, x: c_double, y: c_double, width: c_double, height: c_double):
    external_call["cairo_rectangle", NoneType](cr, x, y, width, height)


def cairo_fill(cr: Cairo):
    external_call["cairo_fill", NoneType](cr)


def cairo_fill_preserve(cr: Cairo):
    external_call["cairo_fill_preserve", NoneType](cr)


def cairo_stroke(cr: Cairo):
    external_call["cairo_stroke", NoneType](cr)


def cairo_paint(cr: Cairo):
    external_call["cairo_paint", NoneType](cr)


def cairo_close_path(cr: Cairo):
    external_call["cairo_close_path", NoneType](cr)


def cairo_new_sub_path(cr: Cairo):
    external_call["cairo_new_sub_path", NoneType](cr)
