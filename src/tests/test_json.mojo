# Copyright (C) 2026 Luís Louro
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Licensed under the GNU General Public License, version 3 or later. The full
# text is in LICENSE.

from model.json import (
    KIND_ARRAY,
    KIND_FLOAT,
    KIND_INT,
    KIND_OBJECT,
    KIND_STRING,
    JsonDoc,
    parse,
    render,
)
from tests.harness import Harness, begin_suite, check, check_eq, check_float, check_int


def run(mut h: Harness) raises:
    begin_suite(h, "model.json")

    # ---- reading -------------------------------------------------------

    var doc = parse("""{"name": "luis", "cigs": 20, "price": 7.5, "ok": true}""")
    check_eq(h, doc.str("name", "?"), "luis", "string member")
    check_int(h, doc.int("cigs", Int64(0)), Int64(20), "integer member")
    check_float(h, doc.float("price", Float64(0.0)), Float64(7.5), "decimal member")
    check(h, doc.boolean("ok", False), "boolean member")
    check_eq(h, doc.str("missing", "fallback"), "fallback", "missing key falls back")
    check_int(h, doc.int("name", Int64(99)), Int64(99), "wrong type falls back")
    check_float(h, doc.float("cigs", Float64(0.0)), Float64(20.0), "int read as float")
    check_int(h, doc.int("price", Int64(0)), Int64(7), "float read as int truncates")
    check_int(h, Int64(doc.count(doc.get("name"))), Int64(0), "scalar has no children")

    var nested = parse("""{"a": {"b": [1, 2, 3]}, "c": []}""")
    var a = nested.get("a")
    check_int(h, Int64(nested.kind_of(a)), Int64(KIND_OBJECT), "nested object kind")
    var ab = nested.member(a, "b")
    check_int(h, Int64(nested.kind_of(ab)), Int64(KIND_ARRAY), "nested array kind")
    check_int(h, Int64(nested.count(ab)), Int64(3), "array length")
    check_int(h, nested.int_at(ab, 2), Int64(3), "array element by position")
    check_int(h, Int64(nested.count(nested.get("c"))), Int64(0), "empty array")

    var esc = parse(r"""{"s": "line\nbreak \"quoted\" tab\there"}""")
    check_eq(h, esc.str("s", ""), "line\nbreak \"quoted\" tab\there", "escapes")

    var uni = parse(r"""{"s": "caf\u00e9 \u2713"}""")
    check_eq(h, uni.str("s", ""), "café \u2713", "unicode escapes")

    var neg = parse("""{"n": -12, "f": -0.25, "e": 1.5e2}""")
    check_int(h, neg.int("n", Int64(0)), Int64(-12), "negative integer")
    check_float(h, neg.float("f", Float64(0.0)), Float64(-0.25), "negative decimal")
    check_float(h, neg.float("e", Float64(0.0)), Float64(150.0), "exponent")

    var ws = parse("  {\n\t\"a\" :  1 ,\n  \"b\" : [ ]\n}  ")
    check_int(h, ws.int("a", Int64(0)), Int64(1), "whitespace tolerant")
    check_int(h, Int64(ws.count(ws.get("b"))), Int64(0), "spaced empty array")

    var nully = parse("""{"a": null, "b": false}""")
    check_eq(h, nully.str("a", "d"), "d", "null is not a string")
    check(h, not nully.boolean("b", True), "false member")

    # Damaged input must not crash; unreadable fields fall back.
    var broken = parse("""{"unterminated": """)
    check_int(h, Int64(broken.count(broken.root)), Int64(1), "unterminated string kept key")
    var broken2 = parse("""{"a": 1,,"b": }""")
    check_int(h, broken2.int("a", Int64(0)), Int64(1), "value before junk survives")
    check_eq(h, parse("").str("a", "d"), "d", "empty document")
    check_eq(h, parse("   ").str("a", "d"), "d", "whitespace-only document")
    check_eq(h, parse("nonsense").str("a", "d"), "d", "garbage document")

    # A document that stopped early is still readable, but it is not a whole
    # one, which is how a truncated file is told apart from a valid one.
    check(h, not broken2.whole_document(), "truncated document is not whole")
    check_int(h, Int64(broken2.count(broken2.root)), Int64(1), "truncated document keeps what it read")
    check(h, parse("""{"a": 1}""").whole_document(), "whole document is whole")
    check(h, parse("  \n{\"a\": [1, 2]}  \t").whole_document(), "trailing space is fine")
    check(h, not parse("""{"a": 1} {"b": 2}""").whole_document(), "two documents are not one")
    check(h, not parse("""{"a": 1""").whole_document(), "missing the close brace")
    check(h, not parse("").whole_document(), "an empty document is not a value")
    check(h, not JsonDoc.empty().whole_document(), "an empty doc has no value")

    # Numeric members read back whether they were written whole or not.
    var numbers = parse("""{"i": 7, "f": 7.5, "s": "x", "n": null}""")
    check_float(h, numbers.get_member_float(0, "i", Float64(-1.0)), Float64(7.0), "int as float")
    check_float(h, numbers.get_member_float(0, "f", Float64(-1.0)), Float64(7.5), "float as float")
    check_float(h, numbers.get_member_float(0, "s", Float64(-1.0)), Float64(-1.0), "text is not a number")
    check_float(h, numbers.get_member_float(0, "n", Float64(-1.0)), Float64(-1.0), "null is not a number")
    check_float(h, numbers.get_member_float(0, "gone", Float64(-1.0)), Float64(-1.0), "absent float fallback")
    check_float(h, numbers.get_member_float(99, "i", Float64(-1.0)), Float64(-1.0), "bad node float fallback")
    check(h, numbers.has_member(0, "f"), "member present")
    check(h, not numbers.has_member(0, "f2"), "member absent")
    check(h, not numbers.has_member(0, "i2"), "absent member reported")

    # ---- writing -------------------------------------------------------

    var out = JsonDoc.object()
    out.set_str(out.root, "name", "luis")
    out.set_int(out.root, "cigs", Int64(20))
    out.set_float(out.root, "price", Float64(7.5))
    out.set_bool(out.root, "active", True)
    var journal = out.set_container(out.root, "journal", KIND_ARRAY)
    _ = out.add_str(journal, "craving")
    _ = out.add_str(journal, "slip")
    var nested_obj = out.add_item(journal, KIND_OBJECT)
    out.set_int(nested_obj, "at", Int64(1789000000))
    out.set_str(nested_obj, "note", "after lunch")

    var text = render(out)
    var back = parse(text)
    check_eq(h, back.str("name", ""), "luis", "round trip string")
    check_int(h, back.int("cigs", Int64(0)), Int64(20), "round trip integer")
    check_float(h, back.float("price", Float64(0.0)), Float64(7.5), "round trip decimal")
    check(h, back.boolean("active", False), "round trip boolean")
    var back_journal = back.get("journal")
    check_int(h, Int64(back.count(back_journal)), Int64(3), "round trip array length")
    check_eq(h, back.text_at(back.child(back_journal, 1)), "slip", "round trip array value")
    var entry = back.child(back_journal, 2)
    check_int(h, back.get_member_int(entry, "at", Int64(0)), Int64(1789000000), "nested object integer")
    check_eq(h, back.get_member_str(entry, "note", ""), "after lunch", "nested object string")

    # Overwriting must replace, not duplicate.
    out.set_str(out.root, "name", "maria")
    out.set_int(out.root, "cigs", Int64(15))
    var again = parse(render(out))
    check_eq(h, again.str("name", ""), "maria", "set overwrites string")
    check_int(h, again.int("cigs", Int64(0)), Int64(15), "set overwrites integer")
    var names = 0
    var members = out.count(out.root)
    var i = 0
    while i < members:
        if out.key_of(out.child(out.root, i)) == "name":
            names += 1
        i += 1
    check_int(h, Int64(names), Int64(1), "no duplicate keys after overwrite")
    check_int(h, Int64(members), Int64(5), "member count unchanged by overwrite")

    # Scalar over a container drops the old children.
    out.set_int(out.root, "journal", Int64(0))
    var scalar = parse(render(out))
    check_int(h, scalar.int("journal", Int64(-1)), Int64(0), "container replaced by scalar")
    check_int(h, Int64(scalar.count(scalar.get("journal"))), Int64(0), "stale children dropped")

    # Re-fetching a container keeps the index, so later appends still work.
    var doc2 = JsonDoc.object()
    var list2 = doc2.set_container(doc2.root, "items", KIND_ARRAY)
    _ = doc2.add_int(list2, Int64(1))
    var list3 = doc2.set_container(doc2.root, "items", KIND_ARRAY)
    _ = doc2.add_int(list3, Int64(2))
    var r2 = parse(render(doc2))
    check_int(h, Int64(r2.count(r2.get("items"))), Int64(2), "container reused not replaced")

    # String escaping on the way out.
    var esc_out = JsonDoc.object()
    esc_out.set_str(esc_out.root, "k", "a\"b\\c\nd")
    var esc_back = parse(render(esc_out))
    check_eq(h, esc_back.str("k", ""), "a\"b\\c\nd", "escaping round trip")
    check_int(h, Int64(render(JsonDoc.empty()).byte_length()), Int64(5), "empty doc renders null")

    check_int(h, Int64(doc.str("name", "?").byte_length()), Int64(4), "returned string length")
