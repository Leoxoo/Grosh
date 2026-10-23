"""Tests for tools/check-logs. From the repository root:

    python3 -B -m unittest discover -s tools

(-B keeps Python from leaving __pycache__ folders in the repository.)

The log is fed to the tool as canned `log show --style ndjson` output, either through --from-file or
through a fake xcrun placed first on PATH, so nothing here needs a simulator.
"""

import ast
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parent
SCRIPT = TOOLS / "check-logs"


def load_script():
    """check-logs has no .py extension, so it is loaded by hand."""
    loader = importlib.machinery.SourceFileLoader("check_logs", str(SCRIPT))
    spec = importlib.util.spec_from_loader("check_logs", loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules["check_logs"] = module
    loader.exec_module(module)
    return module


check_logs = load_script()

BASE = 1_760_000_000  # 2025-10-09 08:53:20 UTC: 04:53:20 where the entries below were written (-0400)
ZONE = timezone(timedelta(hours=-4))
PUBLISHING = "Publishing changes from within view updates is not allowed, this will cause undefined behavior."
WALK = "Transactions → open a transaction"
HEADER = "The app logged errors, faults or runtime issues"


def stamp(at):
    """The timestamp of an entry logged `at` seconds after BASE, written as log show writes it."""
    return datetime.fromtimestamp(BASE + at, ZONE).strftime("%Y-%m-%d %H:%M:%S.%f%z")


def entry(message, at=0.0, *, level="Error", process="Grosh", subsystem="Leoxo.Grosh", category="Import"):
    """One line of `log show --style ndjson`, with the fields it really has."""
    bundles = "/Users/me/Library/Developer/CoreSimulator/Devices/ABC/data/Containers/Bundle/Application/DEF"
    image = f"{bundles}/{process}.app/{process}"
    return {
        "traceID": 3283219123990528, "eventMessage": message, "eventType": "logEvent", "source": None,
        "formatString": message, "activityIdentifier": 0, "subsystem": subsystem, "category": category,
        "threadID": 4242, "senderImageUUID": "6A1C1A5E-0000-0000-0000-000000000001",
        "backtrace": {"frames": [{"imageOffset": 1234, "imageUUID": "6A1C1A5E-0000-0000-0000-000000000001"}]},
        "bootUUID": "", "processImagePath": image, "timestamp": stamp(at),
        "senderImagePath": "/usr/lib/system/libsystem_trace.dylib", "machTimestamp": 123456789,
        "messageType": level, "processImageUUID": "6A1C1A5E-0000-0000-0000-000000000002",
        "processID": 777, "senderProgramCounter": 4096, "parentActivityIdentifier": 0, "timezoneName": "",
    }


def runtime_issue(at=0.0, message=PUBLISHING):
    return entry(message, at, level="Fault", subsystem="com.apple.runtime-issues", category="SwiftUI")


def step(kind, name, at):
    """The UI smoke walk logging `begin <name>` or `end <name>`."""
    return entry(f"{kind} {name}", at, level="Default", process="GroshUITests-Runner",
                 subsystem="Leoxo.GroshUITests", category="Steps")


def ndjson(*records):
    """What log show prints: a line per entry, then the record that says the log is finished."""
    return "\n".join([json.dumps(record, ensure_ascii=False) for record in records] + ['{"finished":1}']) + "\n"


def collect(*records, since=BASE, with_steps=True):
    return check_logs.collect(ndjson(*records).splitlines(), since, with_steps)


def tagged(*records, since=BASE):
    found = collect(*records, since=since)
    check_logs.tag_messages(found.messages, found.marks)
    return [(message.text, message.tag) for message in found.messages]


@contextlib.contextmanager
def local_timezone(posix_tz):
    previous = os.environ.get("TZ")
    os.environ["TZ"] = posix_tz
    time.tzset()
    try:
        yield
    finally:
        if previous is None:
            del os.environ["TZ"]
        else:
            os.environ["TZ"] = previous
        time.tzset()


class WorkDirTestCase(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)

    def write(self, name, text):
        path = self.dir / name
        path.write_text(text, encoding="utf-8")
        return str(path)

    def ignore_file(self, *entries):
        return self.write("ignore.json", json.dumps(list(entries)))

    def log_file(self, *records):
        return self.write("log.ndjson", ndjson(*records))

    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = check_logs.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def check(self, *records, ignore=(), ui=False, since=BASE):
        """Run the tool on a log file holding `records`."""
        argv = ["--since", str(since), "--from-file", self.log_file(*records),
                "--ignore-file", self.ignore_file(*ignore)]
        return self.run_main(*argv, *(["--ui"] if ui else []))


class TimestampTests(unittest.TestCase):
    def test_keeps_the_zone_the_entry_was_written_in(self):
        when = check_logs.parse_timestamp("2025-10-09 04:53:20.250000-0400")
        self.assertEqual(when.timestamp(), BASE + 0.25)
        self.assertEqual(when.strftime("%H:%M:%S"), "04:53:20")

    def test_reads_a_zone_with_a_colon_and_the_letter_z(self):
        self.assertEqual(check_logs.parse_timestamp("2025-10-09 14:23:20.000000+05:30").timestamp(), BASE)
        self.assertEqual(check_logs.parse_timestamp("2025-10-09T08:53:20Z").timestamp(), BASE)

    def test_a_timestamp_without_a_zone_is_local_time(self):
        with local_timezone("EST5"):
            self.assertEqual(check_logs.parse_timestamp("2025-10-09 03:53:20").timestamp(), BASE)

    def test_rejects_what_is_not_a_timestamp(self):
        for text in (None, 5, "", "yesterday", "2025-13-45 99:00:00.000000-0400", "2025-10-09 04:53:20+9999"):
            with self.subTest(text=text):
                self.assertIsNone(check_logs.parse_timestamp(text))


class SimulatorCommandTests(unittest.TestCase):
    APP = ('process == "Grosh" AND (messageType == error OR messageType == fault '
           'OR subsystem == "com.apple.runtime-issues")')
    STEPS = 'subsystem == "Leoxo.GroshUITests" AND category == "Steps"'

    def test_start_is_the_local_time_to_the_second(self):
        with local_timezone("JST-9"):
            self.assertEqual(check_logs.start_argument(BASE), "2025-10-09 17:53:20")
        with local_timezone("EST5"):
            self.assertEqual(check_logs.start_argument(BASE), "2025-10-09 03:53:20")
            self.assertEqual(check_logs.start_argument(BASE + 0.9), "2025-10-09 03:53:20")

    def test_asks_the_booted_simulator_for_the_apps_errors_faults_and_runtime_issues(self):
        with local_timezone("EST5"):
            command = check_logs.simulator_command(BASE, with_steps=False)
        self.assertEqual(command, [
            "xcrun", "simctl", "spawn", "booted", "log", "show", "--style", "ndjson",
            "--start", "2025-10-09 03:53:20", "--predicate", self.APP])

    def test_with_steps_it_also_asks_for_the_step_timeline_and_info_messages(self):
        with local_timezone("EST5"):
            command = check_logs.simulator_command(BASE, with_steps=True)
        self.assertEqual(command, [
            "xcrun", "simctl", "spawn", "booted", "log", "show", "--style", "ndjson", "--info",
            "--start", "2025-10-09 03:53:20", "--predicate", f"({self.APP}) OR ({self.STEPS})"])


class CollectTests(unittest.TestCase):
    def texts(self, *records, **options):
        return [message.text for message in collect(*records, **options).messages]

    def test_keeps_the_apps_errors_and_faults(self):
        self.assertEqual(
            self.texts(entry("an error"), entry("a fault", level="Fault"), entry("another error", level="error")),
            ["[Import] an error", "[Import] a fault", "[Import] another error"])

    def test_leaves_out_the_quieter_levels_and_other_processes(self):
        self.assertEqual(self.texts(
            entry("default", level="Default"), entry("info", level="Info"), entry("debug", level="Debug"),
            entry("not Grosh", process="MobileSafari"), entry("test runner", process="GroshUITests-Runner")), [])

    def test_keeps_a_runtime_issue_at_any_level(self):
        record = entry(PUBLISHING, level="Default", subsystem="com.apple.runtime-issues", category="SwiftUI")
        self.assertEqual(self.texts(record, runtime_issue(1)), [f"[SwiftUI] {PUBLISHING}"] * 2)

    def test_leads_a_message_with_its_category_once(self):
        self.assertEqual(
            self.texts(entry("[Import] already led", category="Import"), entry("no category", category="")),
            ["[Import] already led", "no category"])

    def test_trims_the_message(self):
        self.assertEqual(self.texts(entry("  \n spaced out \n\n")), ["[Import] spaced out"])

    def test_skips_the_closing_record_blank_lines_and_other_events(self):
        lines = ["", '{"finished":1}', json.dumps({"eventType": "timesyncEvent", "timestamp": stamp(1)}), "  "]
        found = check_logs.collect(lines, BASE, True)
        self.assertEqual((found.messages, found.records, found.stray), ([], 2, []))

    def test_notes_lines_that_are_not_json_objects(self):
        lines = ["Filtering the log data using ...", "[1, 2]", json.dumps(entry("kept"))]
        found = check_logs.collect(lines, BASE, False)
        self.assertEqual(len(found.messages), 1)
        self.assertEqual(found.stray, ["Filtering the log data using ...", "[1, 2]"])

    def test_leaves_out_what_was_logged_before_the_run(self):
        self.assertEqual(self.texts(entry("before", -1), entry("at the start", 0), entry("after", 1)),
                         ["[Import] at the start", "[Import] after"])

    def test_puts_messages_in_time_order(self):
        self.assertEqual(self.texts(entry("second", 2), entry("first", 1)), ["[Import] first", "[Import] second"])

    def test_trusts_the_predicate_when_an_entry_has_no_process(self):
        record = entry("no process")
        del record["processImagePath"]
        self.assertEqual(self.texts(record), ["[Import] no process"])

    def test_an_entry_without_a_timestamp_takes_the_time_of_the_one_before(self):
        record = entry("undated")
        del record["timestamp"]
        found = collect(entry("dated", 5), record)
        self.assertEqual([(m.text, m.time, m.clock) for m in found.messages],
                         [("[Import] dated", BASE + 5, "04:53:25"), ("[Import] undated", BASE + 5, "??:??:??")])

    def test_reads_the_step_timeline_only_with_steps(self):
        chatter = entry("chatter", 1, subsystem="Leoxo.GroshUITests", category="Other", level="Default")
        records = (step("begin", WALK, 1), step("end", WALK, 2), chatter)
        self.assertEqual([(m.begins, m.name) for m in collect(*records).marks], [(True, WALK), (False, WALK)])
        self.assertEqual(collect(*records, with_steps=False).marks, [])

    def test_a_steps_entry_that_is_not_a_begin_or_an_end_is_not_a_mark(self):
        self.assertEqual(collect(step("middle of", WALK, 1), step("begin", "", 2)).marks, [])


class TaggingTests(unittest.TestCase):
    def test_a_message_is_tagged_with_the_step_it_was_logged_in(self):
        self.assertEqual(tagged(
            step("begin", WALK, 10), entry("inside", 11), step("end", WALK, 12)), [("[Import] inside", WALK)])

    def test_a_message_outside_a_step_has_no_tag(self):
        found = tagged(entry("before", 1), step("begin", WALK, 10), step("end", WALK, 12), entry("long after", 60))
        self.assertEqual(found, [("[Import] before", None), ("[Import] long after", None)])

    def test_a_message_just_after_a_step_ended_is_put_down_to_it(self):
        self.assertEqual(tagged(step("begin", WALK, 10), step("end", WALK, 12), entry("just after", 13.5),
                                entry("too late", 14.5)),
                         [("[Import] just after", f"after {WALK}"), ("[Import] too late", None)])

    def test_each_message_gets_the_step_of_its_own_time(self):
        self.assertEqual(tagged(
            step("begin", "Home → open", 10), step("end", "Home → open", 12),
            step("begin", "Report → open", 13), entry("in report", 14), entry("in report too", 15),
            step("end", "Report → open", 16), entry("in home?", 11)),
            [("[Import] in home?", "Home → open"), ("[Import] in report", "Report → open"),
             ("[Import] in report too", "Report → open")])

    def test_the_innermost_step_wins(self):
        self.assertEqual(tagged(
            step("begin", "Wallets", 10), step("begin", "Wallets → add", 11), entry("inner", 12),
            step("end", "Wallets → add", 13), entry("outer", 14), step("end", "Wallets", 15)),
            [("[Import] inner", "Wallets → add"), ("[Import] outer", "Wallets")])

    def test_a_step_that_begins_again_replaces_one_whose_end_never_came(self):
        self.assertEqual(tagged(
            step("begin", WALK, 10), step("begin", WALK, 20), entry("second run", 21), step("end", WALK, 22),
            entry("after the end", 40)),
            [("[Import] second run", WALK), ("[Import] after the end", None)])

    def test_an_end_closes_the_steps_inside_it_and_an_end_without_a_begin_is_ignored(self):
        self.assertEqual(tagged(
            step("begin", "Outer", 10), step("begin", "Inner", 11), step("end", "Outer", 12),
            step("end", "Never began", 12.5), entry("after outer", 13), entry("much later", 50)),
            [("[Import] after outer", "after Outer"), ("[Import] much later", None)])

    def test_at_the_same_instant_a_step_begins_before_and_ends_after_the_message(self):
        self.assertEqual(tagged(step("end", WALK, 11), entry("at the edges", 10), step("begin", WALK, 10),
                                entry("also at the edge", 11)),
                         [("[Import] at the edges", WALK), ("[Import] also at the edge", WALK)])

    def test_without_a_timeline_nothing_is_tagged(self):
        self.assertEqual(tagged(entry("one", 1), entry("two", 2)), [("[Import] one", None), ("[Import] two", None)])


class GroupingTests(unittest.TestCase):
    def render(self, *records):
        found = collect(*records)
        check_logs.tag_messages(found.messages, found.marks)
        return check_logs.render(check_logs.group_messages(found.messages))[1:]

    def test_identical_messages_print_once_with_a_count(self):
        self.assertEqual(self.render(runtime_issue(1), runtime_issue(2), runtime_issue(3)),
                         [f"  04:53:21  [SwiftUI] {PUBLISHING} ×3"])

    def test_a_message_logged_once_has_no_count(self):
        self.assertEqual(self.render(entry("once", 1)), ["  04:53:21  [Import] once"])

    def test_messages_that_differ_only_in_whitespace_are_identical(self):
        self.assertEqual(self.render(entry("same", 1), entry(" same\n", 2), entry("same  ", 3)),
                         ["  04:53:21  [Import] same ×3"])

    def test_messages_that_differ_only_in_a_memory_address_are_identical(self):
        self.assertEqual(self.render(entry("lost <Row: 0x600003c2d4a0>", 1), entry("lost <Row: 0x7f8a1c0b2d10>", 2)),
                         ["  04:53:21  [Import] lost <Row: 0x600003c2d4a0> ×2"])

    def test_different_messages_stay_apart_in_the_order_they_first_appeared(self):
        self.assertEqual(self.render(entry("b", 1), entry("a", 2), entry("b", 3), entry("c", 4)),
                         ["  04:53:21  [Import] b ×2", "  04:53:22  [Import] a", "  04:53:24  [Import] c"])

    def test_the_same_text_under_another_category_is_another_message(self):
        self.assertEqual(self.render(entry("failed", 1, category="Import"), entry("failed", 2, category="Export")),
                         ["  04:53:21  [Import] failed", "  04:53:22  [Export] failed"])

    def test_a_group_carries_the_first_step_it_was_seen_in(self):
        self.assertEqual(self.render(
            entry("early", 1), step("begin", "Home → open", 10), entry("early", 11), step("end", "Home → open", 12),
            step("begin", "Report → open", 13), entry("early", 14), step("end", "Report → open", 15)),
            ["  Home → open: [Import] early ×3"])

    def test_a_long_or_multi_line_message_is_cut_short(self):
        lines = self.render(entry("Unable to simultaneously satisfy constraints.\n(\n  <NSLayoutConstraint>\n)", 1),
                            entry("x" * 400, 2))
        self.assertEqual(lines[0], "  04:53:21  [Import] Unable to simultaneously satisfy constraints. …")
        self.assertEqual(lines[1], "  04:53:22  [Import] " + "x" * (check_logs.MAX_MESSAGE - len("[Import] ")) + " …")


class IgnoreListTests(WorkDirTestCase):
    def load(self, *entries):
        return check_logs.load_ignore_list(self.ignore_file(*entries))

    def problems(self, *entries):
        with self.assertRaises(check_logs.ToolError) as caught:
            self.load(*entries)
        return str(caught.exception)

    def test_the_checked_in_list_is_valid(self):
        entries = check_logs.load_ignore_list(TOOLS / "check-logs.ignore")
        self.assertTrue(all(entry.reason for entry in entries))

    def test_an_entry_ignores_the_messages_its_pattern_finds(self):
        entries = self.load({"pattern": r"\[CoreTelephony\] .*carrier", "reason": "System networking noise."})
        self.assertTrue(check_logs.is_ignored("[CoreTelephony] No carrier", entries))
        self.assertFalse(check_logs.is_ignored("[CoreTelephony] SIM", entries))
        self.assertFalse(check_logs.is_ignored("[Import] No carrier", entries))

    def test_a_pattern_is_searched_for_anywhere_and_is_case_sensitive(self):
        entries = self.load({"pattern": "Unable to simultaneously", "reason": "The keyboard's own layout."})
        message = "[LayoutConstraints] Unable to simultaneously satisfy constraints"
        self.assertTrue(check_logs.is_ignored(message, entries))
        self.assertFalse(check_logs.is_ignored("[LayoutConstraints] unable to simultaneously satisfy", entries))

    def test_an_empty_list_ignores_nothing(self):
        self.assertEqual(self.load(), [])

    def test_an_entry_without_a_reason_is_refused(self):
        message = self.problems({"pattern": "Keyboard"})
        self.assertIn('entry 1 (Keyboard): has no "reason"', message)

    def test_a_blank_or_odd_reason_is_refused(self):
        for reason in ("", "   ", None, 5):
            with self.subTest(reason=reason):
                self.assertIn('has no "reason"', self.problems({"pattern": "Keyboard", "reason": reason}))

    def test_an_entry_without_a_pattern_is_refused(self):
        for pattern in (None, "", "  "):
            with self.subTest(pattern=pattern):
                self.assertIn('has no "pattern"', self.problems({"pattern": pattern, "reason": "Because."}))
        self.assertIn('has no "pattern"', self.problems({"reason": "Because."}))

    def test_a_pattern_that_is_not_a_regular_expression_is_refused(self):
        self.assertIn("not a regular expression", self.problems({"pattern": "[unclosed", "reason": "Because."}))

    def test_a_pattern_that_would_ignore_every_message_is_refused(self):
        for pattern in (".*", "(?s).*", "a?", "^"):
            with self.subTest(pattern=pattern):
                self.assertIn("ignore every message", self.problems({"pattern": pattern, "reason": "Because."}))

    def test_an_unknown_key_is_refused(self):
        self.assertIn('has reasons, but an entry holds only "pattern" and "reason"',
                      self.problems({"pattern": "Keyboard", "reasons": "typo"}))

    def test_an_entry_that_is_not_an_object_is_refused(self):
        self.assertIn("entry 1: must be an object", self.problems("Keyboard"))

    def test_every_problem_is_reported_at_once_with_the_number_of_its_entry(self):
        message = self.problems({"pattern": "Fine", "reason": "Because."},
                                {"pattern": "No reason"}, {"reason": "No pattern"})
        self.assertEqual(len(message.splitlines()), 2)
        self.assertIn("entry 2 (No reason)", message)
        self.assertIn("entry 3:", message)

    def test_a_file_that_is_not_a_list_of_entries_is_refused(self):
        for text in ('{"pattern": "x", "reason": "y"}', "", "not json", '"x"'):
            with self.subTest(text=text), self.assertRaises(check_logs.ToolError):
                check_logs.load_ignore_list(self.write("bad.json", text))

    def test_a_missing_file_is_refused(self):
        with self.assertRaises(check_logs.ToolError):
            check_logs.load_ignore_list(self.dir / "missing.json")


class MainTests(WorkDirTestCase):
    WALK_LOG = (
        entry("Could not restore the window", 1, category="Launch"),
        step("begin", WALK, 10),
        runtime_issue(11), runtime_issue(12),
        entry("Unable to simultaneously satisfy constraints.\n(\n  <NSLayoutConstraint:0x600003c2d4a0>\n)", 12.5,
              subsystem="com.apple.UIKit", category="LayoutConstraints"),
        runtime_issue(13),
        step("end", WALK, 14),
        entry("Late message", 15, category="Data"),
        entry("Far later message", 40, category="Data"),
        entry("Not an error", 16, level="Default"),
        entry("Another app's error", 16, process="MobileSafari"),
    )

    def test_prints_what_is_left_grouped_and_exits_1(self):
        code, out, err = self.check(*self.WALK_LOG, ui=True)
        self.assertEqual(code, 1)
        self.assertEqual(err, "")
        self.assertEqual(out.splitlines()[1:], [
            "  04:53:21  [Launch] Could not restore the window",
            f"  {WALK}: [SwiftUI] {PUBLISHING} ×3",
            f"  {WALK}: [LayoutConstraints] Unable to simultaneously satisfy constraints. …",
            f"  after {WALK}: [Data] Late message",
            "  04:54:00  [Data] Far later message",
        ])
        self.assertTrue(out.startswith(HEADER))
        self.assertIn("docs/agents/log-check.md", out.splitlines()[0])

    def test_without_ui_the_messages_carry_only_their_time(self):
        code, out, _ = self.check(*self.WALK_LOG)
        self.assertEqual(code, 1)
        self.assertEqual(out.splitlines()[2], f"  04:53:31  [SwiftUI] {PUBLISHING} ×3")
        self.assertNotIn(WALK, out)

    def test_with_ui_but_no_steps_it_says_so(self):
        code, out, _ = self.check(runtime_issue(1), ui=True)
        self.assertEqual(code, 1)
        self.assertEqual(out.splitlines()[-1], "  (No UI test steps were logged, so these carry only their time.)")

    def test_prints_nothing_and_exits_0_when_nothing_was_logged(self):
        self.assertEqual(self.check(), (0, "", ""))
        self.assertEqual(self.check(entry("fine", level="Default"), ui=True), (0, "", ""))

    def test_prints_nothing_and_exits_0_when_everything_left_is_on_the_ignore_list(self):
        ignore = [{"pattern": r"^\[SwiftUI\] Publishing", "reason": "Test."},
                  {"pattern": "Unable to simultaneously", "reason": "Test."}]
        records = [r for r in self.WALK_LOG if "satisfy" in r["eventMessage"] or r["category"] == "SwiftUI"]
        self.assertEqual(self.check(*records, ignore=ignore, ui=True), (0, "", ""))

    def test_an_ignore_entry_leaves_out_only_what_it_matches(self):
        ignore = [{"pattern": "Publishing changes", "reason": "Test."}]
        code, out, _ = self.check(*self.WALK_LOG, ignore=ignore, ui=True)
        self.assertEqual(code, 1)
        self.assertNotIn("Publishing", out)
        self.assertIn("Could not restore the window", out)

    def test_the_count_is_of_what_the_ignore_list_left(self):
        code, out, _ = self.check(entry("noise 0x600003c2d4a0", 1), entry("noise 0x600003c2d4a8", 2), entry("real", 3),
                                  ignore=[{"pattern": "noise", "reason": "Test."}])
        self.assertEqual((code, out.splitlines()[1:]), (1, ["  04:53:23  [Import] real"]))

    def test_a_message_from_before_the_run_does_not_count(self):
        self.assertEqual(self.check(entry("old", -5), since=BASE), (0, "", ""))

    def test_an_ignore_entry_without_a_reason_stops_the_run_before_the_log_is_read(self):
        argv = ["--since", str(BASE), "--from-file", str(self.dir / "never-read.ndjson"),
                "--ignore-file", self.ignore_file({"pattern": "Keyboard"})]
        code, out, err = self.run_main(*argv)
        self.assertEqual((code, out), (2, ""))
        self.assertIn('entry 1 (Keyboard): has no "reason"', err)
        self.assertNotIn("never-read", err)

    def test_a_log_that_cannot_be_read_exits_2(self):
        code, out, err = self.run_main("--since", str(BASE), "--from-file", str(self.dir / "missing.ndjson"),
                                       "--ignore-file", self.ignore_file())
        self.assertEqual((code, out), (2, ""))
        self.assertIn("cannot read", err)

    def test_a_log_that_is_not_ndjson_exits_2(self):
        path = self.write("log.txt", "Filtering the log data using \"process == 'Grosh'\"\nTimestamp  Thread  Type\n")
        code, out, err = self.run_main("--since", str(BASE), "--from-file", path, "--ignore-file", self.ignore_file())
        self.assertEqual((code, out), (2, ""))
        self.assertIn("not ndjson", err)
        self.assertIn("Filtering the log data", err)

    def test_uses_the_checked_in_ignore_list_by_default(self):
        self.assertEqual(check_logs.IGNORE_FILE, TOOLS / "check-logs.ignore")
        code, out, _ = self.run_main("--since", str(BASE), "--from-file", self.log_file(entry("anything", 1)))
        self.assertEqual((code, out.splitlines()[1:]), (1, ["  04:53:21  [Import] anything"]))

    def test_since_is_required_and_has_to_be_a_unix_time(self):
        for argv in ([], ["--since"], ["--since", "soon"], ["--since", "-1"], ["--since", "nan"]):
            with self.subTest(argv=argv), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as caught:
                    check_logs.main(argv)
                self.assertEqual(caught.exception.code, 2)


class FakeSimulatorTests(WorkDirTestCase):
    """The default path: asking the booted simulator, with a fake xcrun first on PATH."""

    def use_fake_xcrun(self, stdout="", stderr="", exit_code=0, sleep=None):
        bin_dir = self.dir / "bin"
        bin_dir.mkdir(exist_ok=True)
        xcrun = bin_dir / "xcrun"
        xcrun.write_text(
            '#!/bin/sh\n'
            'printf \'%s\\n\' "$@" > "$FAKE_XCRUN_ARGS"\n'
            '[ -n "$FAKE_XCRUN_SLEEP" ] && exec sleep "$FAKE_XCRUN_SLEEP"\n'
            'cat "$FAKE_XCRUN_STDOUT"\n'
            '[ -n "$FAKE_XCRUN_STDERR" ] && printf \'%s\\n\' "$FAKE_XCRUN_STDERR" >&2\n'
            'exit "$FAKE_XCRUN_EXIT"\n')
        xcrun.chmod(0o755)
        self.args_file = self.dir / "args.txt"
        patcher = mock.patch.dict(os.environ, {
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "FAKE_XCRUN_ARGS": str(self.args_file),
            "FAKE_XCRUN_STDOUT": self.write("stdout.ndjson", stdout),
            "FAKE_XCRUN_STDERR": stderr,
            "FAKE_XCRUN_EXIT": str(exit_code),
            "FAKE_XCRUN_SLEEP": "" if sleep is None else str(sleep),
        })
        patcher.start()
        self.addCleanup(patcher.stop)

    def ask(self, *extra):
        return self.run_main("--since", str(BASE), "--ignore-file", self.ignore_file(), *extra)

    def test_reads_the_booted_simulators_log(self):
        self.use_fake_xcrun(stdout=ndjson(*MainTests.WALK_LOG))
        with local_timezone("EST5"):
            code, out, err = self.ask("--ui")
        self.assertEqual((code, err), (1, ""))
        self.assertEqual(out.splitlines()[2], f"  {WALK}: [SwiftUI] {PUBLISHING} ×3")
        self.assertEqual(self.args_file.read_text().splitlines()[:8],
                         ["simctl", "spawn", "booted", "log", "show", "--style", "ndjson", "--info"])
        self.assertIn("2025-10-09 03:53:20", self.args_file.read_text().splitlines())

    def test_a_quiet_log_passes_in_silence(self):
        self.use_fake_xcrun(stdout='{"finished":1}\n')
        self.assertEqual(self.ask(), (0, "", ""))
        self.use_fake_xcrun(stdout="")
        self.assertEqual(self.ask(), (0, "", ""))

    def test_a_failing_log_show_exits_2_with_what_it_said(self):
        self.use_fake_xcrun(stderr="No devices are booted.", exit_code=149)
        code, out, err = self.ask()
        self.assertEqual((code, out), (2, ""))
        self.assertIn("exit 149", err)
        self.assertIn("No devices are booted.", err)
        self.assertIn("xcrun simctl spawn booted log show", err)

    def test_a_missing_xcrun_exits_2(self):
        with mock.patch.dict(os.environ, {"PATH": str(self.dir)}):
            code, out, err = self.ask()
        self.assertEqual((code, out), (2, ""))
        self.assertIn("xcrun is not installed", err)

    def test_a_log_show_that_hangs_exits_2(self):
        self.use_fake_xcrun(sleep=30)
        with mock.patch.object(check_logs, "LOG_SHOW_TIMEOUT", 0.3):
            code, out, err = self.ask()
        self.assertEqual((code, out), (2, ""))
        self.assertIn("took more than", err)


class ScriptTests(WorkDirTestCase):
    def test_is_executable_and_runs_under_python_3(self):
        self.assertTrue(os.access(SCRIPT, os.X_OK))
        self.assertEqual(SCRIPT.read_text(encoding="utf-8").splitlines()[0], "#!/usr/bin/env python3")

    def test_uses_only_syntax_the_systems_python_3_9_reads(self):
        ast.parse(SCRIPT.read_text(encoding="utf-8"), feature_version=(3, 9))

    def run_script(self, *argv, **env):
        clean = {k: v for k, v in os.environ.items()
                 if k not in ("LC_ALL", "LC_CTYPE", "LANG", "PYTHONUTF8", "PYTHONIOENCODING")}
        return subprocess.run([str(SCRIPT), *argv], capture_output=True, env={**clean, **env}, check=False)

    def test_runs_as_tools_check_does_and_prints_utf_8(self):
        log = self.log_file(step("begin", WALK, 10), runtime_issue(11), runtime_issue(12), step("end", WALK, 13))
        for locale in ({}, {"LC_ALL": "C"}):
            with self.subTest(locale=locale):
                done = self.run_script("--since", str(BASE), "--ui", "--from-file", log,
                                       "--ignore-file", self.ignore_file(), **locale)
                self.assertEqual(done.returncode, 1)
                self.assertEqual(done.stderr, b"")
                self.assertEqual(done.stdout.decode("utf-8").splitlines()[1], f"  {WALK}: [SwiftUI] {PUBLISHING} ×2")

    def test_exits_0_in_silence_when_nothing_is_wrong(self):
        done = self.run_script("--since", str(BASE), "--from-file", self.log_file(),
                               "--ignore-file", self.ignore_file())
        self.assertEqual((done.returncode, done.stdout, done.stderr), (0, b"", b""))

    def test_exits_2_when_it_cannot_make_the_check(self):
        done = self.run_script("--since", str(BASE), "--from-file", self.log_file(),
                               "--ignore-file", self.ignore_file({"pattern": "Keyboard"}))
        self.assertEqual((done.returncode, done.stdout), (2, b""))
        self.assertIn(b'has no "reason"', done.stderr)


if __name__ == "__main__":
    unittest.main()
