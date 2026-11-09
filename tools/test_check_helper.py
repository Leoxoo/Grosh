"""Tests for tools/check_helper.py and tools/message_text.py. From the repository root:

    python3 -B -m unittest discover -s tools

tools/tests/check/run.sh covers tools/check end to end; these check the helper's rules one at a time.
"""

import ast
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import check_helper
import message_text

TOOLS = Path(__file__).resolve().parent


def case(name, *children, result="Failed"):
    return {"nodeType": "Test Case", "nodeIdentifier": name, "name": name, "result": result, "children": list(children)}


def failure(text):
    return {"nodeType": "Failure Message", "name": text}


class MessageTextTests(unittest.TestCase):
    def test_first_line_skips_blank_lines(self):
        self.assertEqual(message_text.first_line("\n  \n  kept  \nnext"), "kept")
        self.assertEqual(message_text.first_line(None), "")

    def test_one_line_joins_lines_and_runs_of_spaces(self):
        self.assertEqual(message_text.one_line("a  b\n\tc"), "a b c")

    def test_shorten_cuts_long_text_and_marks_it(self):
        self.assertEqual(message_text.shorten("abcdef", 6), "abcdef")
        self.assertEqual(message_text.shorten("abc defg", 4), "abc …")
        self.assertEqual(message_text.shorten("abc", 6, more=True), "abc …")


class SimulatorTests(unittest.TestCase):
    def runtimes(self, *devices):
        return {"com.apple.CoreSimulator.SimRuntime.iOS-26-4": list(devices)}

    def test_is_booted_reads_the_listed_state(self):
        runtimes = self.runtimes({"udid": "A", "state": "Booted"}, {"udid": "B", "state": "Shutdown"})
        self.assertTrue(check_helper.is_booted("A", runtimes))
        self.assertFalse(check_helper.is_booted("B", runtimes))
        self.assertFalse(check_helper.is_booted("C", runtimes))

    def test_simulator_prints_its_state(self):
        runtimes = self.runtimes({"udid": "A", "name": "iPhone 17 Pro", "state": "Shutdown"})
        with mock.patch.object(check_helper, "available_devices", return_value=runtimes), \
                mock.patch("builtins.print") as printed:
            self.assertEqual(check_helper.simulator("/nonexistent"), 0)
        printed.assert_called_once_with("A\tdown\tiPhone 17 Pro (iOS 26.4)")

    def test_a_check_logs_run_is_skipped_when_simctl_cannot_list(self):
        with tempfile.TemporaryDirectory() as root:
            tool = Path(root, "tools", "check-logs")
            tool.parent.mkdir()
            tool.write_text("#!/bin/sh\n")
            tool.chmod(0o755)
            with mock.patch.object(check_helper, "available_devices", side_effect=check_helper.Problem("no")):
                code, lines = check_helper.check_logs(root, "0", False, "A")
        self.assertEqual(code, 0)
        self.assertIn("tools/check-logs skipped", lines[0])


class ResultTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root)
        os.makedirs(os.path.join(self.root, "GroshTests"))
        Path(self.root, "GroshTests", "FooTests.swift").touch()

    def test_a_failure_names_its_file_by_its_path_in_the_repository(self):
        cases = [(None, case("FooTests/bar()", failure("FooTests.swift:3: Expectation failed:\nwhy")))]
        lines = check_helper.failure_lines(cases, {}, 1, self.root)
        self.assertEqual(lines, ["FAIL FooTests/bar(): GroshTests/FooTests.swift:3: Expectation failed: why"])

    def test_a_place_at_the_end_in_parentheses_is_read_too(self):
        cases = [(None, case("FooTests/bar()", failure("Crashed (FooTests.swift:9)")))]
        self.assertEqual(check_helper.failure_lines(cases, {}, 1, self.root),
                         ["FAIL FooTests/bar(): GroshTests/FooTests.swift:9: Crashed"])

    def test_failures_beyond_five_per_test_are_counted(self):
        texts = [failure("failure {}".format(number)) for number in range(8)]
        lines = check_helper.failure_lines([(None, case("FooTests/bar()", *texts))], {}, 1, self.root)
        self.assertEqual(len(lines), 6)
        self.assertEqual(lines[-1], "FAIL FooTests/bar(): ... and 3 more failures")

    def test_without_failure_messages_the_summary_gives_the_reason(self):
        summary = {"testFailures": [{"testIdentifierString": "FooTests/bar()", "failureText": "timed out"}]}
        lines = check_helper.failure_lines([(None, case("FooTests/bar()"))], summary, 1, self.root)
        self.assertEqual(lines, ["FAIL FooTests/bar(): timed out"])

    def test_a_long_message_is_cut(self):
        lines = check_helper.failure_lines([(None, case("FooTests/bar()", failure("x" * 600)))], {}, 1, self.root)
        self.assertEqual(lines, ["FAIL FooTests/bar(): " + "x" * check_helper.LONGEST_MESSAGE + " …"])

    def test_a_build_error_gives_its_line_counted_from_1(self):
        url = "file://{}/Grosh/A.swift#EndingLineNumber=4&StartingLineNumber=4".format(self.root)
        build = {"errors": [{"message": "Oops", "sourceURL": url},
                            {"message": "Command SwiftCompile failed with a nonzero exit code"}]}
        self.assertEqual(check_helper.build_errors(build, self.root), ["ERROR Grosh/A.swift:5: Oops"])

    def test_build_errors_of_an_unexpected_shape_fail_loudly(self):
        with self.assertRaises(check_helper.Problem):
            check_helper.build_errors({"errors": "none"}, self.root)


class ScriptTests(unittest.TestCase):
    def test_uses_only_syntax_the_systems_python_3_9_reads(self):
        for name in ("check_helper.py", "message_text.py"):
            with self.subTest(name=name):
                ast.parse((TOOLS / name).read_text(encoding="utf-8"), feature_version=(3, 9))


if __name__ == "__main__":
    unittest.main()
