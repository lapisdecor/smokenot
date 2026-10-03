"""A small JSON reader/writer built on a flat node arena.

The state file is the app's only persistence, so this covers the JSON subset
that gets written: objects, arrays, strings, integers, decimals, booleans and
null.

Nodes live in one flat `List[JsonNode]` and refer to each other by index
rather than nesting values, which keeps the type non-recursive (Mojo cannot
destroy a value that contains itself) and makes rendering a single walk.
Members keep insertion order so the written file is stable and readable.
"""

from lib.text import (
    append_codepoint_as_utf8,
    bytes_to_string,
    format_fixed,
    format_int,
    parse_float,
    parse_int,
    string_to_bytes,
)


comptime KIND_NULL: Int32 = 0
comptime KIND_BOOL: Int32 = 1
comptime KIND_INT: Int32 = 2
comptime KIND_FLOAT: Int32 = 3
comptime KIND_STRING: Int32 = 4
comptime KIND_ARRAY: Int32 = 5
comptime KIND_OBJECT: Int32 = 6
comptime NO_NODE: Int = -1
comptime QUOTE: Byte = Byte(34)
comptime BACKSLASH: Byte = Byte(92)
comptime LETTER_N: Byte = Byte(110)
comptime LETTER_R: Byte = Byte(114)
comptime LETTER_T: Byte = Byte(116)
comptime NEWLINE: Byte = Byte(10)
comptime CARRIAGE: Byte = Byte(13)
comptime TAB: Byte = Byte(9)
comptime MINUS_BYTE: Byte = Byte(45)
comptime PLUS_SIGN: Byte = Byte(43)
comptime LETTER_E: Byte = Byte(101)
comptime UPPER_E: Byte = Byte(69)


@fieldwise_init
struct JsonNode:
    var kind: Int32
    var flag: Bool
    var whole: Int64
    var decimal: Float64
    var text: String
    var key: String
    var children: List[Int]

    def __init__(out self, kind: Int32):
        self.kind = kind
        self.flag = False
        self.whole = Int64(0)
        self.decimal = Float64(0.0)
        self.text = String("")
        self.key = String("")
        self.children = List[Int]()

    def is_container(self) -> Bool:
        return self.kind == KIND_OBJECT or self.kind == KIND_ARRAY


struct JsonDoc:
    var nodes: List[JsonNode]
    var root: Int
    # Set by the parser: false when the input stopped in the middle of a
    # document or carried extra data after it. A document built in code is
    # complete by definition.
    var complete: Bool

    def __init__(out self):
        self.nodes = List[JsonNode]()
        self.root = NO_NODE
        self.complete = True

    # ---- construction --------------------------------------------------

    @staticmethod
    def object() -> JsonDoc:
        var doc = JsonDoc()
        doc.root = doc._add(KIND_OBJECT, String(""))
        return doc^

    @staticmethod
    def array() -> JsonDoc:
        var doc = JsonDoc()
        doc.root = doc._add(KIND_ARRAY, String(""))
        return doc^

    @staticmethod
    def empty() -> JsonDoc:
        """A document that parsed to nothing; every lookup falls back."""
        return JsonDoc()

    def _add(mut self, kind: Int32, key: String) -> Int:
        var node = JsonNode(kind)
        node.key = key
        self.nodes.append(node^)
        return len(self.nodes) - 1

    def _link(mut self, parent: Int, child: Int):
        self.nodes[parent].children.append(child)

    # ---- lookup --------------------------------------------------------

    def valid(self) -> Bool:
        return self.root != NO_NODE

    def whole_document(self) -> Bool:
        """True when this is a document that was read to its end cleanly."""
        return self.root != NO_NODE and self.complete

    def kind_of(self, node: Int) -> Int32:
        if node < 0 or node >= len(self.nodes):
            return KIND_NULL
        return self.nodes[node].kind

    def member(self, node: Int, key: String) -> Int:
        """Index of a member of an object node, or NO_NODE."""
        if node < 0 or node >= len(self.nodes):
            return NO_NODE
        if self.nodes[node].kind != KIND_OBJECT:
            return NO_NODE
        var i = 0
        var total = self.count(node)
        while i < total:
            var idx = self.nodes[node].children[i]
            if self.nodes[idx].key == key:
                return idx
            i += 1
        return NO_NODE

    def get(self, key: String) -> Int:
        return self.member(self.root, key)

    def text_at(self, node: Int) -> String:
        if node < 0 or node >= len(self.nodes):
            return String("")
        return self.nodes[node].text

    def str(self, key: String, fallback: String) -> String:
        var found = self.get(key)
        if found == NO_NODE or self.nodes[found].kind != KIND_STRING:
            return fallback
        return self.nodes[found].text

    def int(self, key: String, fallback: Int64) -> Int64:
        var found = self.get(key)
        if found == NO_NODE:
            return fallback
        var kind = self.nodes[found].kind
        if kind == KIND_INT:
            return self.nodes[found].whole
        if kind == KIND_FLOAT:
            return Int64(self.nodes[found].decimal)
        if kind == KIND_STRING:
            var text = self.nodes[found].text
            if is_numeric(text):
                return parse_int(text)
            return fallback
        return fallback

    def float(self, key: String, fallback: Float64) -> Float64:
        var found = self.get(key)
        if found == NO_NODE:
            return fallback
        var kind = self.nodes[found].kind
        if kind == KIND_FLOAT:
            return self.nodes[found].decimal
        if kind == KIND_INT:
            return Float64(self.nodes[found].whole)
        if kind == KIND_STRING:
            var text = self.nodes[found].text
            if is_numeric(text):
                return parse_float(text)
            return fallback
        return fallback

    def boolean(self, key: String, fallback: Bool) -> Bool:
        var found = self.get(key)
        if found == NO_NODE:
            return fallback
        var kind = self.nodes[found].kind
        if kind == KIND_BOOL:
            return self.nodes[found].flag
        if kind == KIND_INT:
            return self.nodes[found].whole != Int64(0)
        if kind == KIND_STRING:
            return self.nodes[found].text == "true"
        return fallback

    # ---- mutation ------------------------------------------------------

    def set_str(mut self, node: Int, key: String, value: String):
        var existing = self.member(node, key)
        var fresh = self._add(KIND_STRING, key)
        self.nodes[fresh].text = value
        self._replace_or_link(node, existing, fresh, False)

    def set_int(mut self, node: Int, key: String, value: Int64):
        var existing = self.member(node, key)
        var fresh = self._add(KIND_INT, key)
        self.nodes[fresh].whole = value
        self._replace_or_link(node, existing, fresh, False)

    def set_float(mut self, node: Int, key: String, value: Float64):
        var existing = self.member(node, key)
        var fresh = self._add(KIND_FLOAT, key)
        self.nodes[fresh].decimal = value
        self._replace_or_link(node, existing, fresh, False)

    def set_bool(mut self, node: Int, key: String, value: Bool):
        var existing = self.member(node, key)
        var fresh = self._add(KIND_BOOL, key)
        self.nodes[fresh].flag = value
        self._replace_or_link(node, existing, fresh, False)

    def set_container(mut self, node: Int, key: String, kind: Int32) -> Int:
        """Create (or fetch) a container member and return its index."""
        var existing = self.member(node, key)
        if existing != NO_NODE and self.nodes[existing].is_container():
            return existing
        var fresh = self._add(kind, key)
        self._replace_or_link(node, existing, fresh, True)
        # A replaced member keeps its old index, so hand that one back.
        return fresh if existing == NO_NODE else existing

    def add_item(mut self, array: Int, kind: Int32) -> Int:
        var fresh = self._add(kind, String(""))
        self._link(array, fresh)
        return fresh

    def add_str(mut self, array: Int, value: String) -> Int:
        var fresh = self._add(KIND_STRING, String(""))
        self.nodes[fresh].text = value
        self._link(array, fresh)
        return fresh

    def add_int(mut self, array: Int, value: Int64) -> Int:
        var fresh = self._add(KIND_INT, String(""))
        self.nodes[fresh].whole = value
        self._link(array, fresh)
        return fresh

    def count(self, node: Int) -> Int:
        if node < 0 or node >= len(self.nodes):
            return 0
        return len(self.nodes[node].children)

    def child(self, node: Int, position: Int) -> Int:
        if position < 0 or position >= self.count(node):
            return NO_NODE
        return self.nodes[node].children[position]

    def key_of(self, node: Int) -> String:
        if node < 0 or node >= len(self.nodes):
            return String("")
        return self.nodes[node].key

    def int_at(self, array: Int, position: Int) -> Int64:
        var found = self.child(array, position)
        if found == NO_NODE:
            return Int64(0)
        if self.nodes[found].kind == KIND_INT:
            return self.nodes[found].whole
        if self.nodes[found].kind == KIND_FLOAT:
            return Int64(self.nodes[found].decimal)
        return Int64(0)

    def str_at(self, array: Int, position: Int) -> String:
        var found = self.child(array, position)
        if found == NO_NODE:
            return String("")
        return self.nodes[found].text

    def set_member_str(mut self, node: Int, key: String, value: String):
        self.set_str(node, key, value)

    def set_member_int(mut self, node: Int, key: String, value: Int64):
        self.set_int(node, key, value)

    def set_member_float(mut self, node: Int, key: String, value: Float64):
        self.set_float(node, key, value)

    def set_member_bool(mut self, node: Int, key: String, value: Bool):
        self.set_bool(node, key, value)

    def has_member(self, node: Int, key: String) -> Bool:
        """True when the key is present, whatever kind of value it holds."""
        return self.member(node, key) != NO_NODE

    def get_member_int(self, node: Int, key: String, fallback: Int64) -> Int64:
        var found = self.member(node, key)
        if found == NO_NODE:
            return fallback
        if self.nodes[found].kind == KIND_INT:
            return self.nodes[found].whole
        if self.nodes[found].kind == KIND_FLOAT:
            return Int64(self.nodes[found].decimal)
        return fallback

    def get_member_float(self, node: Int, key: String, fallback: Float64) -> Float64:
        """Numeric member as a float, accepting a whole number for it too.

        A value written as `7` has to read back the same as one written as
        `7.00`, so the integer kind is converted rather than rejected.
        """
        var found = self.member(node, key)
        if found == NO_NODE:
            return fallback
        if self.nodes[found].kind == KIND_FLOAT:
            return self.nodes[found].decimal
        if self.nodes[found].kind == KIND_INT:
            return Float64(self.nodes[found].whole)
        return fallback

    def get_member_str(self, node: Int, key: String, fallback: String) -> String:
        var found = self.member(node, key)
        if found == NO_NODE:
            return fallback
        if self.nodes[found].kind == KIND_STRING:
            return self.nodes[found].text
        return fallback

    def get_member_bool(self, node: Int, key: String, fallback: Bool) -> Bool:
        var found = self.member(node, key)
        if found == NO_NODE:
            return fallback
        if self.nodes[found].kind == KIND_BOOL:
            return self.nodes[found].flag
        return fallback

    def _replace_or_link(
        mut self, node: Int, existing: Int, fresh: Int, becomes_container: Bool
    ):
        if existing == NO_NODE:
            self._link(node, fresh)
            return
        # Overwrite in place so the member keeps its position and any index a
        # caller already holds stays valid. Children are dropped when the kind
        # changes; otherwise they belong to the caller's container.
        if self.nodes[existing].kind != self.nodes[fresh].kind:
            self.nodes[existing].children = List[Int]()
        self.nodes[existing].kind = self.nodes[fresh].kind
        self.nodes[existing].flag = self.nodes[fresh].flag
        self.nodes[existing].whole = self.nodes[fresh].whole
        self.nodes[existing].decimal = self.nodes[fresh].decimal
        self.nodes[existing].text = self.nodes[fresh].text


def is_numeric(text: String) -> Bool:
    """True when the text is a JSON number, so a string can be coerced."""
    var bytes = string_to_bytes(text)
    if len(bytes) == 0:
        return False
    var i = 0
    if bytes[0] == MINUS_BYTE:
        i = 1
    var digits = 0
    var dots = 0
    while i < len(bytes):
        var b = bytes[i]
        if b >= Byte(48) and b <= Byte(57):
            digits += 1
        elif b == Byte(46):
            dots += 1
        elif b == LETTER_E or b == UPPER_E or b == PLUS_SIGN or b == MINUS_BYTE:
            # Exponent marker: accepted, the parser itself is lenient.
            pass
        else:
            return False
        i += 1
    return digits > 0 and dots <= 1


# ---------------------------------------------------------------- parsing


struct Parser:
    var data: List[Byte]
    var pos: Int

    var damaged: Bool

    def __init__(out self, text: String) raises:
        self.data = string_to_bytes(text)
        self.pos = 0
        self.damaged = False

    def at_end(self) -> Bool:
        return self.pos >= len(self.data)

    def peek(self) -> Byte:
        if self.at_end():
            return Byte(0)
        return self.data[self.pos]

    def skip_space(mut self):
        while not self.at_end():
            var b = self.data[self.pos]
            if b == Byte(32) or b == Byte(9) or b == Byte(10) or b == Byte(13):
                self.pos += 1
            else:
                break

    def eat(mut self, b: Byte) -> Bool:
        if self.peek() == b:
            self.pos += 1
            return True
        return False

    def parse(mut self, mut doc: JsonDoc) raises:
        """Fill in `doc` from the input, keeping whatever could be read.

        Damaged input never raises: whatever was readable before the damage is
        still in the document. `doc.complete` says whether the input ended
        cleanly, so a caller reading a file can tell a whole document from a
        truncated one instead of silently accepting the valid prefix.
        """
        self.skip_space()
        if self.at_end():
            doc.complete = True
            return
        doc.root = self.parse_value(doc)
        self.skip_space()
        doc.complete = self.at_end() and not self.damaged


    def parse_value(mut self, mut doc: JsonDoc) raises -> Int:
        self.skip_space()
        if self.at_end():
            return doc._add(KIND_NULL, String(""))
        var b = self.data[self.pos]
        if b == Byte(123):
            return self.parse_object(doc)
        if b == Byte(91):
            return self.parse_array(doc)
        if b == Byte(34):
            var node = doc._add(KIND_STRING, String(""))
            var text = self.parse_string()
            doc.nodes[node].text = text
            return node
        return self.parse_atom(doc)

    def parse_atom(mut self, mut doc: JsonDoc) raises -> Int:
        var b = self.peek()
        if b == Byte(116):
            return self.parse_word(doc, "true", KIND_BOOL, True)
        if b == Byte(102):
            return self.parse_word(doc, "false", KIND_BOOL, False)
        if b == Byte(110):
            return self.parse_word(doc, "null", KIND_NULL, False)
        return self.parse_number(doc)

    def parse_word(mut self, mut doc: JsonDoc, word: String, kind: Int32, flag: Bool) -> Int:
        var letters = string_to_bytes(word)
        var i = 0
        while i < len(letters):
            if self.at_end() or self.data[self.pos] != letters[i]:
                self.damaged = True
                return doc._add(KIND_NULL, String(""))
            self.pos += 1
            i += 1
        var node = doc._add(kind, String(""))
        doc.nodes[node].flag = flag
        return node

    def parse_string_into(mut self, mut buf: List[Byte]) -> Bool:
        if not self.eat(Byte(34)):
            return False
        while not self.at_end():
            var b = self.data[self.pos]
            self.pos += 1
            if b == Byte(34):
                return True
            if b == Byte(92):
                if self.at_end():
                    self.damaged = True
                    break
                var esc = self.data[self.pos]
                self.pos += 1
                if esc == Byte(110):
                    buf.append(Byte(10))
                elif esc == Byte(116):
                    buf.append(Byte(9))
                elif esc == Byte(114):
                    buf.append(Byte(13))
                elif esc == Byte(98):
                    buf.append(Byte(8))
                elif esc == Byte(102):
                    buf.append(Byte(12))
                elif esc == Byte(117):
                    self.parse_codepoint(buf)
                else:
                    buf.append(esc)
            else:
                buf.append(b)
        self.damaged = True
        return True

    def parse_string(mut self) raises -> String:
        var buf = List[Byte]()
        _ = self.parse_string_into(buf)
        return bytes_to_string(buf)

    def parse_codepoint(mut self, mut buf: List[Byte]):
        var value = 0
        var i = 0
        while i < 4:
            if self.at_end():
                self.damaged = True
                return
            var d = _hex_value(self.data[self.pos])
            self.pos += 1
            if d < 0:
                self.damaged = True
                return
            value = value * 16 + d
            i += 1
        append_codepoint_as_utf8(buf, value)

    def parse_number(mut self, mut doc: JsonDoc) raises -> Int:
        var start = self.pos
        var is_float = False
        if self.peek() == Byte(45):
            self.pos += 1
        while not self.at_end():
            var b = self.data[self.pos]
            if b >= Byte(48) and b <= Byte(57):
                self.pos += 1
            elif b == Byte(46) or b == Byte(101) or b == Byte(69) or b == Byte(43):
                is_float = True
                self.pos += 1
            else:
                break
        var slice = List[Byte]()
        var i = start
        while i < self.pos:
            slice.append(self.data[i])
            i += 1
        var text = bytes_to_string(slice)
        if is_float:
            var node = doc._add(KIND_FLOAT, String(""))
            doc.nodes[node].decimal = parse_float(text)
            return node
        var node = doc._add(KIND_INT, String(""))
        doc.nodes[node].whole = parse_int(text)
        return node

    def parse_array(mut self, mut doc: JsonDoc) raises -> Int:
        var array_node = doc._add(KIND_ARRAY, String(""))
        _ = self.eat(Byte(91))
        self.skip_space()
        if self.peek() == Byte(93):
            self.pos += 1
            return array_node
        while not self.at_end():
            var child = self.parse_value(doc)
            doc._link(array_node, child)
            self.skip_space()
            if self.peek() == Byte(44):
                self.pos += 1
                continue
            if not self.eat(Byte(93)):
                self.damaged = True
            break
        return array_node

    def parse_object(mut self, mut doc: JsonDoc) raises -> Int:
        var object_node = doc._add(KIND_OBJECT, String(""))
        _ = self.eat(Byte(123))
        self.skip_space()
        if self.peek() == Byte(125):
            self.pos += 1
            return object_node
        while not self.at_end():
            self.skip_space()
            var key = self.parse_string()
            self.skip_space()
            if not self.eat(Byte(58)):
                self.damaged = True
                break
            var value = self.parse_value(doc)
            doc.nodes[value].key = key^
            doc._link(object_node, value)
            self.skip_space()
            if self.peek() == Byte(44):
                self.pos += 1
                continue
            if not self.eat(Byte(125)):
                self.damaged = True
            break
        return object_node


def _hex_value(b: Byte) -> Int:
    if b >= Byte(48) and b <= Byte(57):
        return Int(b - Byte(48))
    if b >= Byte(97) and b <= Byte(102):
        return Int(b - Byte(97)) + 10
    if b >= Byte(65) and b <= Byte(70):
        return Int(b - Byte(65)) + 10
    return -1


def parse(text: String) raises -> JsonDoc:
    var doc = JsonDoc.empty()
    var p = Parser(text)
    p.parse(doc)
    return doc^


# --------------------------------------------------------------- rendering


struct Renderer:
    """Walks a JsonDoc and appends pretty-printed JSON to a byte buffer.

    A struct rather than free functions because `List.append` mutates, and Mojo
    only allows a mutating call through a `mut self` receiver.
    """

    var buf: List[Byte]

    def __init__(out self):
        self.buf = List[Byte]()

    def byte(mut self, b: Byte):
        self.buf.append(b)

    def letters(mut self, word: String):
        var letters = string_to_bytes(word)
        var i = 0
        while i < len(letters):
            self.buf.append(letters[i])
            i += 1

    def indent(mut self, depth: Int):
        var i = 0
        while i < depth:
            self.buf.append(Byte(32))
            self.buf.append(Byte(32))
            i += 1

    def quoted(mut self, text: String):
        self.byte(QUOTE)
        for b in text.bytes():
            if b == QUOTE:
                self.byte(BACKSLASH)
                self.byte(QUOTE)
            elif b == BACKSLASH:
                self.byte(BACKSLASH)
                self.byte(BACKSLASH)
            elif b == NEWLINE:
                self.byte(BACKSLASH)
                self.byte(LETTER_N)
            elif b == CARRIAGE:
                self.byte(BACKSLASH)
                self.byte(LETTER_R)
            elif b == TAB:
                self.byte(BACKSLASH)
                self.byte(LETTER_T)
            else:
                self.byte(b)
        self.byte(QUOTE)

    def number(mut self, node: Int, ref doc: JsonDoc):
        var kind = doc.kind_of(node)
        if kind == KIND_BOOL:
            if doc.nodes[node].flag:
                self.letters("true")
            else:
                self.letters("false")
        elif kind == KIND_INT:
            self.letters(format_int(doc.nodes[node].whole))
        elif kind == KIND_FLOAT:
            self.letters(format_fixed(doc.nodes[node].decimal, 2))
        else:
            self.letters("null")

    def container(mut self, node: Int, depth: Int, ref doc: JsonDoc) raises:
        var kind = doc.kind_of(node)
        var open: Byte = Byte(123) if kind == KIND_OBJECT else Byte(91)
        var close: Byte = Byte(125) if kind == KIND_OBJECT else Byte(93)
        self.byte(open)
        var total = doc.count(node)
        var i = 0
        while i < total:
            if i > 0:
                self.byte(Byte(44))
            self.byte(Byte(10))
            self.indent(depth + 1)
            var kid = doc.child(node, i)
            if kind == KIND_OBJECT:
                self.quoted(doc.key_of(kid))
                self.byte(Byte(58))
                self.byte(Byte(32))
            self.node(kid, depth + 1, doc)
            i += 1
        if total > 0:
            self.byte(Byte(10))
            self.indent(depth)
        self.byte(close)

    def node(mut self, node: Int, depth: Int, ref doc: JsonDoc) raises:
        if doc.kind_of(node) == KIND_OBJECT or doc.kind_of(node) == KIND_ARRAY:
            self.container(node, depth, doc)
            return
        if doc.kind_of(node) == KIND_STRING:
            self.quoted(doc.text_at(node))
            return
        self.number(node, doc)

    def finish(mut self) raises -> String:
        return bytes_to_string(self.buf)


def render(ref doc: JsonDoc) raises -> String:
    """Pretty-print with two-space indentation and a trailing newline."""
    var r = Renderer()
    if doc.valid():
        r.node(doc.root, 0, doc)
    else:
        r.letters("null")
    r.byte(Byte(10))
    return r.finish()
