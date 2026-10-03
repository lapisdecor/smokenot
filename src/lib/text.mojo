"""String, ASCII and number helpers used across smokenot.

Mojo strings are UTF-8 and deliberately restrict positional access, so this
module works on whole strings and single-codepoint slices rather than raw byte
pointers. Nothing here hands out a pointer into a temporary.
"""

comptime DIGITS = "0123456789"
comptime MINUS = "-"
comptime DOT_BYTE: Byte = Byte(46)


def c_string_to_string(address: Int) raises -> String:
    """Build a String from a NUL terminated C string at `address`.

    GTK hands text back as a borrowed C string, so it has to be walked and
    copied out before the String owns its bytes. A null address, which is what
    GTK returns for "no title", reads as an empty string.
    """
    if address == 0:
        return String("")
    var data = Pointer[Byte, MutUntrackedOrigin](unsafe_from_address=address)
    var buf = List[Byte]()
    var i = 0
    while True:
        var b = data[unsafe_offset=i]
        if b == Byte(0):
            break
        buf.append(b)
        i += 1
    return bytes_to_string(buf)


def bytes_to_string(data: List[Byte]) raises -> String:
    """Build a String from raw bytes (UTF-8).

    Copies through a scratch allocation that is released as soon as the String
    owns its bytes, so no span ever outlives the buffer behind it.
    """
    from std.ffi import c_size_t, external_call

    var count = len(data)
    if count == 0:
        return String("")
    var raw = external_call[
        "malloc", Optional[Pointer[UInt8, MutUntrackedOrigin]]
    ](c_size_t(count + 1))
    if not raw:
        return String("")
    var buf = raw.value()
    var i = 0
    while i < count:
        buf[unsafe_offset=i] = data[i]
        i += 1
    buf[unsafe_offset=count] = Byte(0)
    var text = String(from_utf8=Span(unsafe_ptr=buf, length=count))
    external_call["free", NoneType](buf)
    return text


def append_codepoint_as_utf8(mut buf: List[Byte], codepoint: Int):
    """Append a Unicode code point to `buf` as UTF-8 bytes."""
    if codepoint < 0x80:
        buf.append(Byte(codepoint))
    elif codepoint < 0x800:
        buf.append(Byte(0xC0 | (codepoint >> 6)))
        buf.append(Byte(0x80 | (codepoint & 0x3F)))
    elif codepoint < 0x10000:
        buf.append(Byte(0xE0 | (codepoint >> 12)))
        buf.append(Byte(0x80 | ((codepoint >> 6) & 0x3F)))
        buf.append(Byte(0x80 | (codepoint & 0x3F)))
    else:
        buf.append(Byte(0xF0 | (codepoint >> 18)))
        buf.append(Byte(0x80 | ((codepoint >> 12) & 0x3F)))
        buf.append(Byte(0x80 | ((codepoint >> 6) & 0x3F)))
        buf.append(Byte(0x80 | (codepoint & 0x3F)))


def string_to_bytes(text: String) -> List[Byte]:
    """Explode a String into its raw UTF-8 bytes."""
    var out = List[Byte]()
    for b in text.bytes():
        out.append(b)
    return out^


def slice_to_string(text: String, start: Int, stop: Int) raises -> String:
    """Copy the bytes of `text` from `start` up to `stop` into a new String.

    Byte offsets are what the callers here work in, and every offset they pass
    sits on an ASCII delimiter, so a slice never lands inside a multi-byte
    character.
    """
    var all = string_to_bytes(text)
    var out = List[Byte]()
    var i = start
    while i < stop and i < len(all):
        out.append(all[i])
        i += 1
    return bytes_to_string(out)


def digit_value(ch: String) -> Int:
    """ASCII value of a single digit character, or -1 if not a digit."""
    var idx = 0
    while idx < 10:
        if ch == String(DIGITS[byte=idx]):
            return idx
        idx += 1
    return -1


def is_digit_str(ch: String) -> Bool:
    return digit_value(ch) >= 0


def parse_int(text: String) -> Int64:
    """Parse an optionally negative integer. Returns 0 when malformed."""
    var t = text.strip()
    if t.byte_length() == 0:
        return Int64(0)
    var negative = t[byte=0] == MINUS
    var start: Int = 1 if negative else 0
    var value: Int64 = 0
    var seen = False
    var i = start
    while i < t.byte_length():
        var d = digit_value(String(t[byte=i]))
        if d < 0:
            return Int64(0)
        value = value * Int64(10) + Int64(d)
        seen = True
        i += 1
    if not seen:
        return Int64(0)
    if negative:
        return -value
    return value


def parse_float(text: String) -> Float64:
    """Parse a decimal number with an optional sign and exponent."""
    var t = text.strip()
    if t.byte_length() == 0:
        return Float64(0.0)
    var negative = t[byte=0] == MINUS
    var start: Int = 1 if negative else 0
    var whole: Float64 = 0.0
    var i = start
    while i < t.byte_length():
        var d = digit_value(String(t[byte=i]))
        if d < 0:
            break
        whole = whole * Float64(10.0) + Float64(d)
        i += 1
    if i < t.byte_length() and t[byte=i] == ".":
        i += 1
        var scale: Float64 = 0.1
        while i < t.byte_length():
            var d = digit_value(String(t[byte=i]))
            if d < 0:
                break
            whole = whole + Float64(d) * scale
            scale = scale * Float64(0.1)
            i += 1
    # Optional exponent, as produced by JSON such as 1.5e2.
    if i < t.byte_length() and (t[byte=i] == "e" or t[byte=i] == "E"):
        i += 1
        var exp_negative = False
        if i < t.byte_length() and (t[byte=i] == "+" or t[byte=i] == MINUS):
            exp_negative = t[byte=i] == MINUS
            i += 1
        var power: Int = 0
        while i < t.byte_length():
            var d = digit_value(String(t[byte=i]))
            if d < 0:
                break
            power = power * 10 + d
            i += 1
        if exp_negative:
            while power > 0:
                whole = whole / Float64(10.0)
                power -= 1
        else:
            while power > 0:
                whole = whole * Float64(10.0)
                power -= 1
    if negative:
        return -whole
    return whole


def format_int(value: Int64) -> String:
    """Render an Int64 in plain digits, independent of any locale."""
    if value == Int64(0):
        return String("0")
    var negative = value < Int64(0)
    var v = value
    if negative:
        v = -v
    var reversed = String("")
    while v > Int64(0):
        var d = Int(v % Int64(10))
        reversed += String(DIGITS[byte=d])
        v = v // Int64(10)
    var out = String("")
    if negative:
        out += String(MINUS)
    var i = reversed.byte_length() - 1
    while i >= 0:
        out += String(reversed[byte=i])
        i -= 1
    return out


def format_fixed(value: Float64, decimals: Int) -> String:
    """Render a Float64 with a fixed number of decimals.

    Avoids locale and exponent formatting so the same string appears in every
    language. Rounds half away from zero.
    """
    var negative = value < Float64(0.0)
    var v = value
    if negative:
        v = -v
    var scale: Int64 = Int64(1)
    var d = 0
    while d < decimals:
        scale = scale * Int64(10)
        d += 1
    var scaled: Int64 = Int64(v * Float64(scale) + Float64(0.5))
    var whole = scaled // scale
    var frac = scaled % scale
    var out = String("")
    if negative:
        out += String(MINUS)
    out += format_int(whole)
    if decimals > 0:
        out += String(".")
        var frac_text = format_int(frac)
        var pad = decimals - frac_text.byte_length()
        while pad > 0:
            out += String("0")
            pad -= 1
        out += frac_text
    return out


def format_money(value: Float64) -> String:
    return format_fixed(value, 2)


def group_with(digits: String, sep: String) -> String:
    """Group a plain integer string in threes: 1234567 becomes '1,234,567'."""
    var count = digits.byte_length()
    if count == 0:
        return digits
    var negative = digits[byte=0] == MINUS
    var start: Int = 1 if negative else 0
    var out = String("")
    if negative:
        out += String(MINUS)
    var i = start
    while i < count:
        var remaining = count - i
        if i > start and remaining % 3 == 0:
            out += sep
        out += String(digits[byte=i])
        i += 1
    return out


def group_thousands(digits: String) -> String:
    """Space-group a plain integer string: 1234567 becomes '1 234 567'."""
    return group_with(digits, " ")


def split_on(text: String, sep: String) -> List[String]:
    """Split on a single-character separator, dropping empty fields.

    Slices the source string rather than rebuilding characters one byte at a
    time, because `String(byte)` yields a number as text, not that character.
    """
    var out = List[String]()
    var sep_byte = Byte(32)
    for b in sep.bytes():
        sep_byte = b
    var start = 0
    var i = 0
    var count = text.byte_length()
    for b in text.bytes():
        if b == sep_byte:
            if i > start:
                out.append(String(text[byte=start:i]))
            start = i + 1
        i += 1
    if count > start:
        out.append(String(text[byte=start:count]))
    return out^


def english_plural(count: Int64) -> Bool:
    """English counts zero as plural: "0 cigarettes", "1 cigarette"."""
    return count != Int64(1)


def split_at_dot(text: String) -> Tuple[String, String]:
    """Split a plain decimal string into whole and fraction parts."""
    var count = text.byte_length()
    var cut = -1
    var i = 0
    for b in text.bytes():
        if b == DOT_BYTE and i > 0:
            cut = i
        i += 1
    if cut < 0:
        return (text, String(""))
    return (String(text[byte=0:cut]), String(text[byte=cut + 1 : count]))
