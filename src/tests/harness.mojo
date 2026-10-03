"""Minimal assertion harness.

Mojo 1.1 ships no `mojo test` command and no `testing` module, and it has no
mutable globals, so the project carries its own. State is threaded through a
Harness value that the runner owns; failures exit non-zero for build.sh.
"""

from std.ffi import c_int, external_call


struct Harness:
    var checks: Int
    var failures: Int
    var current: String

    def __init__(out self):
        self.checks = 0
        self.failures = 0
        self.current = String("")


def begin_suite(mut h: Harness, name: String):
    h.current = name
    print("--", name)


def check(mut h: Harness, condition: Bool, label: String):
    h.checks += 1
    if not condition:
        h.failures += 1
        print("   FAIL:", h.current, "/", label)


def check_eq(mut h: Harness, actual: StringSlice, expected: StringSlice, label: String):
    """Both sides are copied into owned Strings first.

    A caller that reads a field out of a list hands over a view of that list,
    and letting the view turn into a String implicitly builds something that
    does not always compare equal to the same text written as a literal.
    """
    h.checks += 1
    var got = String(actual)
    var want = String(expected)
    if got != want:
        h.failures += 1
        print("   FAIL:", h.current, "/", label)
        print("        expected:", want)
        print("        actual:  ", got)


def check_int(mut h: Harness, actual: Int64, expected: Int64, label: String):
    check_eq(h, String(actual), String(expected), label)


def check_float(mut h: Harness, actual: Float64, expected: Float64, label: String):
    # Tolerance keeps decimal arithmetic from being brittle.
    var diff = actual - expected
    if diff < Float64(0.0):
        diff = -diff
    h.checks += 1
    if diff > Float64(0.0001):
        h.failures += 1
        print("   FAIL:", h.current, "/", label)
        print("        expected:", expected)
        print("        actual:  ", actual)


def finish(mut h: Harness) raises:
    print("")
    if h.failures == 0:
        print("all", h.checks, "checks passed")
        return
    print(h.failures, "of", h.checks, "checks FAILED")
    external_call["exit", NoneType](c_int(1))
