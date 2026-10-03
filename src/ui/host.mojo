"""The bridge between GTK callbacks and the app's own state.

GTK hands a callback one untyped pointer and nothing else, and the app has a
model that Mojo owns. So both live in C memory that the callbacks can reach:

* `UiState` is a bag of widget pointers and counters, small and plain, so it
  can sit in a fixed block.
* the model is a `State` in a block of its own, reached through its address,
  which `UiState` carries.

Nothing is ever copied out of either block. A callback reads a field, changes
it and leaves the value where it is, so what the window shows and what the
model holds cannot drift apart.

`UiState` deliberately has no constructor: its block is zeroed before use, and
GTK handles start out as nothing, which is exactly the zero pointer.
"""

from gtk import gtk
from model.state import State
from std.sys import size_of

comptime Widget = gtk.Widget


struct UiState(TrivialRegisterPassable, ImplicitlyCopyable):
    var model_address: Int
    var window: Widget
    var stack: Widget
    var dash_days: Widget
    var dash_money: Widget
    var dash_cigs: Widget
    var dash_life: Widget
    var dash_slips: Widget
    var dash_since: Widget
    var dash_next: Widget
    var dash_next_in: Widget
    var dash_bar: Widget
    var dash_quit_now: Widget
    var dash_note: Widget
    var miles_box: Widget
    var miles_done: Widget
    var sos_area: Widget
    var sos_clock: Widget
    var sos_phase: Widget
    var sos_body: Widget
    var sos_start: Widget
    var sos_stop: Widget
    var journal_box: Widget
    var journal_count: Widget
    var journal_note: Widget
    var journal_craving_button: Widget
    var journal_slip_button: Widget
    var settings_heading: Widget
    var settings_intro: Widget
    var settings_cigs: Widget
    var settings_pack_size: Widget
    var settings_pack_price: Widget
    var settings_cigs_label: Widget
    var settings_pack_size_label: Widget
    var settings_pack_price_label: Widget
    var settings_language_label: Widget
    var settings_calendar: Widget
    var settings_date_label: Widget
    var settings_date_caption: Widget
    var settings_status: Widget
    var settings_save: Widget
    var settings_about: Widget
    var settings_path: Widget
    var settings_lang: Widget
    var settings_reset: Widget
    var switcher: Widget
    var sos_left: Int32
    var sos_running: Int32
    var breathe: Int32
    var reset_armed: Int32

    def widgets(self) -> List[Widget]:
        """Every label the language switch has to rewrite, in build order."""
        var out = List[Widget]()
        out.append(self.settings_cigs_label)
        out.append(self.settings_pack_size_label)
        out.append(self.settings_pack_price_label)
        out.append(self.settings_date_label)
        out.append(self.settings_status)
        out.append(self.dash_note)
        out.append(self.dash_since)
        out.append(self.miles_done)
        out.append(self.sos_body)
        out.append(self.journal_count)
        out.append(self.settings_about)
        out.append(self.settings_path)
        out.append(self.settings_save)
        out.append(self.sos_start)
        out.append(self.sos_stop)
        return out^


def is_null(widget: Widget) -> Bool:
    """Whether a widget handle is empty.

    A handle out of a zeroed block is a null pointer, and a pointer is not
    something the language will turn into a `Bool` on its own.
    """
    return Int(widget) == 0


def take_ui() raises -> Widget:
    """A zeroed block big enough for a `UiState`."""
    return gtk.alloc(size_of[UiState]())


def take_model() raises -> Widget:
    """A zeroed block big enough for the model."""
    return gtk.alloc(size_of[State]())


def ui_of(user_data: Widget) -> Pointer[UiState, MutUntrackedOrigin]:
    return gtk.state_of[UiState](user_data)


def model_of(user_data: Widget) -> Pointer[State, MutUntrackedOrigin]:
    """The model behind a callback's user data."""
    return Pointer[State, MutUntrackedOrigin](
        unsafe_from_address=ui_of(user_data)[].model_address
    )


def place_model(block: Widget, ref model: State):
    """Put a copy of the model in its own block.

    Field by field, because writing a whole struct into raw memory is not
    something the language offers. After this the block, not the local, holds
    the model, and only the block is ever touched.
    """
    var slot = Pointer[State, MutUntrackedOrigin](unsafe_from_address=Int(block))
    slot[].version = model.version
    slot[].profile = model.profile
    slot[].journal_blob = model.journal_blob
    slot[].loaded_from_disk = model.loaded_from_disk
