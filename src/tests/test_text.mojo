from lib.text import (
    c_string_to_string,
    digit_value,
    english_plural,
    format_fixed,
    format_int,
    format_money,
    group_thousands,
    group_with,
    parse_float,
    parse_int,
    split_on,
    split_at_dot,
)
from tests.harness import Harness, begin_suite, check, check_eq, check_float, check_int


def run(mut h: Harness) raises:
    begin_suite(h, "lib.text")

    check_int(h, parse_int("42"), Int64(42), "parse_int positive")
    check_int(h, parse_int("-17"), Int64(-17), "parse_int negative")
    check_int(h, parse_int(""), Int64(0), "parse_int empty")
    check_int(h, parse_int(" 7 "), Int64(7), "parse_int trims")
    check_int(h, parse_int("abc"), Int64(0), "parse_int garbage is zero")
    check_int(h, parse_int("12x"), Int64(0), "parse_int trailing garbage")

    check_float(h, parse_float("3.75"), Float64(3.75), "parse_float decimal")
    check_float(h, parse_float("-0.5"), Float64(-0.5), "parse_float negative")
    check_float(h, parse_float("12"), Float64(12.0), "parse_float integer")
    check_float(h, parse_float("0.05"), Float64(0.05), "parse_float small")

    check_eq(h, format_int(Int64(0)), "0", "format_int zero")
    check_eq(h, format_int(Int64(1234567)), "1234567", "format_int large")
    check_eq(h, format_int(Int64(-42)), "-42", "format_int negative")

    check_eq(h, format_fixed(Float64(3.14159), 2), "3.14", "format_fixed rounds")
    check_eq(h, format_fixed(Float64(2.0), 2), "2.00", "format_fixed pads")
    check_eq(h, format_fixed(Float64(0.5), 0), "1", "format_fixed rounds half up")
    check_eq(h, format_fixed(Float64(-2.5), 1), "-2.5", "format_fixed negative")
    check_eq(h, format_money(Float64(1234.5)), "1234.50", "format_money")

    check_eq(h, group_thousands("1234567"), "1 234 567", "group thousands")
    check_eq(h, group_thousands("100"), "100", "group exact hundred")
    check_eq(h, group_thousands("1234"), "1 234", "group four digits")
    check_eq(h, group_thousands("-4200"), "-4 200", "group negative")
    check_eq(h, group_thousands(""), "", "group empty")

    check_int(h, Int64(digit_value("7")), Int64(7), "digit_value")
    check_int(h, Int64(digit_value("x")), Int64(-1), "digit_value rejects")

    check_eq(h, group_with("1234567", ","), "1,234,567", "group with comma")
    check_eq(h, group_with("1234567", "."), "1.234.567", "group with dot")
    check_eq(h, group_with("12", ","), "12", "group leaves short numbers")
    check_eq(h, group_with("-1234", "."), "-1.234", "group negative with dot")

    check(h, not english_plural(Int64(1)), "english plural singular")
    check(h, english_plural(Int64(0)), "english plural zero")
    check(h, english_plural(Int64(2)), "english plural plural")

    var split = split_at_dot("1234.50")
    check_eq(h, split[0], "1234", "split whole part")
    check_eq(h, split[1], "50", "split fraction part")
    var whole = split_at_dot("42")
    check_eq(h, whole[0], "42", "split without a dot")
    check_eq(h, whole[1], "", "split missing fraction")
    var neg = split_at_dot("-3.25")
    check_eq(h, neg[0], "-3", "split keeps the sign on the whole part")
    check_eq(h, neg[1], "25", "split negative fraction")

    # ---- splitting ------------------------------------------------------

    var words = split_on("a bb  ccc ", " ")
    check_int(h, Int64(len(words)), Int64(3), "split drops empty fields")
    check_eq(h, words[0], "a", "first field")
    check_eq(h, words[2], "ccc", "last field, trailing space dropped")
    check_int(h, Int64(len(split_on("", " "))), Int64(0), "split of nothing")
    check_int(h, Int64(len(split_on("a,,b", ","))), Int64(2), "split on a comma")
    var single = split_on("only", " ")
    check_eq(h, single[0], "only", "one field is still one field")
    var keyed = split_on("unit_minute unit_minutes", " ")
    check_eq(h, keyed[1], "unit_minutes", "key lists split on spaces")

    # A null address is what GTK returns for "no text", and has to read empty
    # rather than walk off into nothing.
    check_eq(h, c_string_to_string(Int(0)), "", "null c string reads empty")

    check(h, True, "harness self check")
