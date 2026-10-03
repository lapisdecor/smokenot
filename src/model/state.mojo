# Copyright (C) 2026 Luís Louro
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Licensed under the GNU General Public License, version 3 or later. The full
# text is in LICENSE.

"""Everything the app persists: the profile and the craving journal.

State is written as a single JSON document. Loading never fails: a missing,
truncated or hand-edited file falls back to defaults, and out-of-range numbers
are clamped, so a bad file can cost the user their settings but can never stop
the app from starting.
"""

from i18n.strings import LANG_PT, language_from_code
from lib import sys
from lib.text import bytes_to_string, format_int, parse_int, slice_to_string, split_on, string_to_bytes
from model.json import KIND_ARRAY, KIND_OBJECT, JsonDoc, parse, render
from model.stats import Gains, compute


comptime SCHEMA_VERSION: Int = 1
comptime KIND_CRAVING: Int = 0
comptime KIND_SLIP: Int = 1

comptime DEFAULT_CIGS_PER_DAY: Int64 = Int64(20)
comptime DEFAULT_PACK_SIZE: Int64 = Int64(20)
comptime DEFAULT_PACK_PRICE: Float64 = Float64(7.0)
comptime MAX_CIGS_PER_DAY: Int64 = Int64(500)
comptime MAX_PACK_SIZE: Int64 = Int64(100)
comptime MAX_PACK_PRICE: Float64 = Float64(10000.0)
comptime MAX_JOURNAL_ENTRIES: Int = 500


struct Profile(ImplicitlyCopyable):
    var cigs_per_day: Int64
    var pack_size: Int64
    var pack_price: Float64
    var quit_epoch: Int64
    var language: Int
    var created_epoch: Int64
    var configured: Bool
    var quit_started: Bool

    def __init__(out self):
        # Suggestion values for onboarding, so the field can start empty while
        # still being pre-filled. `configured` is what decides whether the
        # dashboard or the setup wizard opens, and it is false until the user
        # has answered the questions.
        self.cigs_per_day = DEFAULT_CIGS_PER_DAY
        self.pack_size = DEFAULT_PACK_SIZE
        self.pack_price = DEFAULT_PACK_PRICE
        self.quit_epoch = Int64(0)
        self.language = LANG_PT
        self.created_epoch = Int64(0)
        self.configured = False
        self.quit_started = False

    def is_configured(self) -> Bool:
        return (
            self.configured
            and self.cigs_per_day > Int64(0)
            and self.pack_size > Int64(0)
        )

    def mark_configured(mut self):
        self.configured = True

    def gains(self, now_epoch: Int64) -> Gains:
        return compute(
            self.cigs_per_day, self.pack_price, self.pack_size, self.quit_epoch, now_epoch
        )

    def is_planned(self, now_epoch: Int64) -> Bool:
        """True while the count is waiting for a day that has not come yet."""
        if self.quit_epoch <= Int64(0) or self.quit_started:
            return False
        return sys.local_day_number(self.quit_epoch) > sys.local_day_number(now_epoch)

    def is_quit_day(self, now_epoch: Int64) -> Bool:
        """True on the chosen day itself, while the count has not begun.

        Counted on the calendar rather than the clock, so a date stored at
        midnight still counts as today for the whole of today, and the quit
        button is on screen from the first moment of the day to the last.
        """
        if self.quit_epoch <= Int64(0) or self.quit_started:
            return False
        return sys.local_day_number(self.quit_epoch) == sys.local_day_number(now_epoch)

    def set_quit_day(mut self, chosen_midnight: Int64, now_epoch: Int64):
        """Point the count at a day picked on the calendar.

        A day that is today starts counting now, the moment the settings are
        saved, and not at midnight: a person who picks today means "from now",
        and a count that had been running since midnight would credit them with
        hours they were still smoking.

        A day still to come stays a plan, stored as that day's midnight, and the
        count only begins when the day arrives and the user says so. A day
        already gone is kept as it is, so an edit that lands in the past counts
        from that midnight rather than pretending the count never started.
        """
        if chosen_midnight <= Int64(0):
            return
        if sys.local_day_number(chosen_midnight) == sys.local_day_number(now_epoch):
            self.quit_epoch = now_epoch
            self.quit_started = True
            return
        self.quit_epoch = chosen_midnight
        self.quit_started = chosen_midnight < now_epoch

    def start_counting(mut self, now_epoch: Int64):
        """Begin the count from this moment, for a day that has arrived.

        This is what the "Quit now!" button does: the date chose the day, and
        the person quitting chooses the moment.
        """
        self.quit_epoch = now_epoch
        self.quit_started = True

    def cost_per_cigarette(self) -> Float64:
        return self.pack_price / Float64(self.pack_size)

    def clamp(mut self):
        """Pull every field into a range the arithmetic can rely on."""
        if self.cigs_per_day < Int64(0):
            self.cigs_per_day = Int64(0)
        if self.cigs_per_day > MAX_CIGS_PER_DAY:
            self.cigs_per_day = MAX_CIGS_PER_DAY
        if self.pack_size < Int64(1):
            self.pack_size = Int64(1)
        if self.pack_size > MAX_PACK_SIZE:
            self.pack_size = MAX_PACK_SIZE
        if self.pack_price < Float64(0.0):
            self.pack_price = Float64(0.0)
        if self.pack_price > MAX_PACK_PRICE:
            self.pack_price = MAX_PACK_PRICE
        if self.quit_epoch < Int64(0):
            self.quit_epoch = Int64(0)
        if self.created_epoch < Int64(0):
            self.created_epoch = Int64(0)
        if self.language != 0 and self.language != 1:
            self.language = LANG_PT
        # A count that is running needs a moment to count from, and a date with
        # no moment behind it is only ever a plan, so the two cannot be left
        # disagreeing. Which of the two a date is comes from the flag, not from
        # the clock: a day still to come is a plan today and the press that
        # starts it is what makes it a count.
        if self.quit_epoch <= Int64(0):
            self.quit_started = False


struct JournalEntry(ImplicitlyCopyable):
    var epoch: Int64
    var kind: Int
    var note: String

    def __init__(out self, epoch: Int64, kind: Int, note: String):
        self.epoch = epoch
        self.kind = kind
        self.note = note

    def is_slip(self) -> Bool:
        return self.kind == KIND_SLIP


comptime BYTE_BACKSLASH: Byte = Byte(0x5C)
comptime BYTE_NEWLINE: Byte = Byte(0x0A)
comptime BYTE_N: Byte = Byte(0x6E)
comptime BYTE_SPACE: Byte = Byte(0x20)
comptime BYTE_0: Byte = Byte(0x30)


def _escape_note(note: String) raises -> String:
    var out = List[Byte]()
    for b in note.bytes():
        if b == BYTE_BACKSLASH:
            out.append(BYTE_BACKSLASH)
            out.append(BYTE_BACKSLASH)
        elif b == BYTE_NEWLINE:
            out.append(BYTE_BACKSLASH)
            out.append(BYTE_N)
        else:
            out.append(b)
    return bytes_to_string(out)


def _unescape_note(note: String) raises -> String:
    var all = string_to_bytes(note)
    var out = List[Byte]()
    var i = 0
    while i < len(all):
        if all[i] == BYTE_BACKSLASH and i + 1 < len(all):
            if all[i + 1] == BYTE_N:
                out.append(BYTE_NEWLINE)
            else:
                out.append(all[i + 1])
            i += 2
            continue
        out.append(all[i])
        i += 1
    return bytes_to_string(out)



struct State(ImplicitlyCopyable):
    """The profile plus the journal, in the form the window keeps in memory.

    The journal rides along as one string rather than a `List` so the whole
    state stays copyable. That matters because GTK calls back from C, and
    reaching a stack value from a callback means taking its address, which
    Mojo only allows for a copyable value. `entries()` decodes the blob when a
    caller wants to walk the journal.
    """
    var version: Int
    var profile: Profile
    var journal_blob: String
    var loaded_from_disk: Bool

    def __init__(out self):
        self.version = SCHEMA_VERSION
        self.profile = Profile()
        self.journal_blob = String("")
        self.loaded_from_disk = False

    def is_configured(self) -> Bool:
        return self.profile.is_configured()

    def start_fresh(mut self, now_epoch: Int64, quit_epoch: Int64):
        """Reset to an unconfigured state, as after Delete all data."""
        self.version = SCHEMA_VERSION
        self.profile = Profile()
        self.profile.created_epoch = now_epoch
        # The date goes through the same rule as any other, so a reset that
        # passes this moment starts counting here and one that passes a day
        # still to come is a plan like any other.
        self.profile.set_quit_day(quit_epoch, now_epoch)
        self.journal_blob = String("")
        self.loaded_from_disk = False

    def add_entry(mut self, epoch: Int64, kind: Int, note: String) raises:
        """Record a craving or a slip, newest first.

        The newest goes in at the front and the cap then drops from the back,
        which is the oldest, so the blob reads in the order the journal is
        shown in.
        """
        if kind != KIND_CRAVING and kind != KIND_SLIP:
            return
        var entries = self.entries()
        entries.insert(0, JournalEntry(epoch, kind, note))
        while len(entries) > MAX_JOURNAL_ENTRIES:
            _ = entries.pop()
        self.journal_blob = _encode_journal(entries)

    def entries(self) raises -> List[JournalEntry]:
        """The journal in order, newest first."""
        return _decode_journal(self.journal_blob)

    def entry_count(self) -> Int:
        """How many entries the journal holds.

        Counted straight off the blob, so a once-a-second refresh does not
        build a list of entries it is only going to measure.
        """
        var n = 0
        for b in string_to_bytes(self.journal_blob):
            if b == BYTE_NEWLINE:
                n += 1
        return n

    def slip_count(self) -> Int:
        """How many of the entries are slips, also read off the blob."""
        var n = 0
        var field = 0
        var kind = Int64(0)
        for b in string_to_bytes(self.journal_blob):
            if b == BYTE_NEWLINE:
                if field > 0 and kind == Int64(KIND_SLIP):
                    n += 1
                field = 0
                kind = Int64(0)
            elif b == BYTE_SPACE:
                field += 1
            elif field == 1:
                kind = kind * Int64(10) + Int64(Int(b) - Int(BYTE_0))
        # Every line carries its newline, so this only fires on a blob that was
        # cut short. Counting it anyway keeps the total honest.
        if field > 0 and kind == Int64(KIND_SLIP):
            n += 1
        return n

    def newest_entry_epoch(self) -> Int64:
        """The epoch of the newest entry, which is the first line of the blob."""
        var value = Int64(0)
        for b in string_to_bytes(self.journal_blob):
            if b == BYTE_SPACE:
                break
            value = value * Int64(10) + Int64(Int(b) - Int(BYTE_0))
        return value

    def entries_of_kind(self, kind: Int) raises -> List[JournalEntry]:
        var out = List[JournalEntry]()
        for entry in _decode_journal(self.journal_blob):
            if entry.kind == kind:
                out.append(JournalEntry(entry.epoch, entry.kind, entry.note))
        return out^


# ------------------------------------------------------- journal in a string
#
# One entry per line: epoch, kind, then the note with backslashes and newlines
# escaped. A space separates the first two fields from the note, so a note may
# hold spaces of its own without needing them escaped.


def _encode_journal(ref entries: List[JournalEntry]) raises -> String:
    var out = String("")
    for entry in entries:
        out += format_int(entry.epoch) + String(" ")
        out += format_int(Int64(entry.kind)) + String(" ")
        out += _escape_note(entry.note)
        out += String("\n")
    return out^


def _decode_journal(blob: String) raises -> List[JournalEntry]:
    var out = List[JournalEntry]()
    if blob.byte_length() == 0:
        return out^
    for line in split_on(blob, "\n"):
        if line.byte_length() == 0:
            continue
        var first = _field(line, 0)
        var second = _field(line, 1)
        if first == "" or second == "":
            continue
        out.append(JournalEntry(parse_int(first), Int(parse_int(second)), _unescape_note(_rest(line))))
    return out^


def _field(ref line: String, index: Int) raises -> String:
    """The text before the space at `index`, or nothing if it is missing."""
    var start = 0
    var seen = 0
    var i = 0
    while i < line.byte_length():
        if line[byte=i] == " ":
            if seen == index:
                return slice_to_string(line, start, i)
            seen += 1
            start = i + 1
        i += 1
    return ""


def _rest(ref line: String) raises -> String:
    """Everything after the second space, which is the note."""
    var separator = _space_at(line, 1)
    if separator == 0:
        return String("")
    return slice_to_string(line, separator + 1, line.byte_length())


def _space_at(ref line: String, index: Int) -> Int:
    """The offset of the space that closes field `index`, or 0 if there is none."""
    var seen = 0
    var i = 0
    while i < line.byte_length():
        if line[byte=i] == " ":
            if seen == index:
                return i
            seen += 1
        i += 1
    return 0


# ------------------------------------------------------------ persistence


def defaults() -> State:
    return State()


def load(path: String) raises -> State:
    """Read state from `path`, falling back to defaults on any problem."""
    var out = State()
    var text = sys.read_file(path)
    if text.byte_length() == 0:
        return out^
    var doc = parse(text)
    if not doc.valid():
        return out^
    if doc.kind_of(doc.root) != KIND_OBJECT or not doc.complete:
        return out^

    out.version = Int(doc.int("version", Int64(SCHEMA_VERSION)))

    _read_profile(doc, out.profile)
    out.journal_blob = _encode_journal(_read_journal(doc))
    out.profile.clamp()
    out.loaded_from_disk = True
    return out^


def _read_profile(ref doc: JsonDoc, mut profile: Profile):
    var node = doc.get("profile")
    if node < 0 or doc.kind_of(node) != KIND_OBJECT:
        return
    profile.cigs_per_day = doc.get_member_int(node, "cigs_per_day", DEFAULT_CIGS_PER_DAY)
    profile.pack_size = doc.get_member_int(node, "pack_size", DEFAULT_PACK_SIZE)
    profile.pack_price = doc.get_member_float(node, "pack_price", DEFAULT_PACK_PRICE)
    profile.quit_epoch = doc.get_member_int(node, "quit_epoch", Int64(0))
    profile.language = language_from_code(doc.get_member_str(node, "language", String("pt_PT")))
    profile.created_epoch = doc.get_member_int(node, "created_epoch", Int64(0))
    # A file written before this field existed still counts as configured when
    # it carries a habit, so hand-edited state does not send the user back to
    # the wizard.
    if not doc.has_member(node, "configured"):
        profile.configured = profile.cigs_per_day > Int64(0)
    else:
        profile.configured = doc.get_member_bool(node, "configured", False)
    # The same goes for the flag that says the count is under way. A date
    # already in the past was a running count before the flag existed, and a
    # date still to come was a plan, so the timestamp decides.
    if not doc.has_member(node, "quit_started"):
        profile.quit_started = profile.quit_epoch > Int64(0) and profile.quit_epoch <= sys.now_epoch()
    else:
        profile.quit_started = doc.get_member_bool(node, "quit_started", False)


def _read_journal(ref doc: JsonDoc) -> List[JournalEntry]:
    var out = List[JournalEntry]()
    var node = doc.get("journal")
    if node < 0 or doc.kind_of(node) != KIND_ARRAY:
        return out^
    # The file lists the newest entry first, the same order the list keeps, so
    # it is read front to back. An over-long file then loses its oldest
    # entries, which are the ones at the end.
    var kept = 0
    while kept < MAX_JOURNAL_ENTRIES and kept < doc.count(node):
        var entry_node = doc.child(node, kept)
        if doc.kind_of(entry_node) == KIND_OBJECT:
            var kind_text = doc.get_member_str(entry_node, "kind", String("craving"))
            var kind = KIND_SLIP if kind_text == "slip" else KIND_CRAVING
            out.append(
                JournalEntry(
                    doc.get_member_int(entry_node, "epoch", Int64(0)),
                    kind,
                    doc.get_member_str(entry_node, "note", String("")),
                )
            )
        kept += 1
    return out^


def save(path: String, ref state: State) raises:
    """Write the state document, creating the data directory if needed."""
    sys.write_file(path, render(to_json(state)))


def to_json(ref state: State) raises -> JsonDoc:
    var doc = JsonDoc.object()
    doc.set_int(doc.root, "version", Int64(state.version))

    var profile = doc.set_container(doc.root, "profile", KIND_OBJECT)
    doc.set_member_int(profile, "cigs_per_day", state.profile.cigs_per_day)
    doc.set_member_int(profile, "pack_size", state.profile.pack_size)
    doc.set_member_float(profile, "pack_price", state.profile.pack_price)
    doc.set_member_int(profile, "quit_epoch", state.profile.quit_epoch)
    doc.set_member_int(profile, "created_epoch", state.profile.created_epoch)
    doc.set_member_str(
        profile, "language", String("pt_PT") if state.profile.language == LANG_PT else String("en")
    )
    doc.set_member_bool(profile, "configured", state.profile.configured)
    doc.set_member_bool(profile, "quit_started", state.profile.quit_started)

    var journal = doc.set_container(doc.root, "journal", KIND_ARRAY)
    for entry in state.entries():
        var node = doc.add_item(journal, KIND_OBJECT)
        doc.set_member_int(node, "epoch", entry.epoch)
        doc.set_member_str(node, "kind", String("slip") if entry.is_slip() else String("craving"))
        doc.set_member_str(node, "note", entry.note)

    return doc^
