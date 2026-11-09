"""What tools/check reads that bash cannot: the simulator list and the result bundle, both JSON.

    python3 tools/check_helper.py simulator <project.pbxproj>
        prints the chosen simulator as UDID <tab> booted|down <tab> name (iOS version)
    python3 tools/check_helper.py report <bundle> <log> <status> <seconds> <ui> <only> <results> <root> <since> <udid>
        prints the outcome and exits with tools/check's status
"""

import json
import os
import re
import subprocess
import sys
import time
from urllib.parse import parse_qs, unquote, urlparse

from message_text import first_line, one_line
from message_text import shorten as shorten_to

PREFERRED_SIMULATOR = "iPhone 17 Pro"
UI_TESTS = "GroshUITests"
FAILURES_PER_TEST = 5
LONGEST_MESSAGE = 500
CRASH_REPORTS = os.environ.get("GROSH_CRASH_REPORTS") or os.path.expanduser("~/Library/Logs/DiagnosticReports")
CRASH_FRAMES = 8  # the frames of the crashed thread that are printed
CRASH_REPORTS_SHOWN = 2
CRASH_WAIT = 10  # seconds for macOS to write a crash report once the tests have ended

# Where xcresulttool puts a failure's place: "ReimbursementTests.swift:42: Expectation failed: ...", or at the end in
# parentheses.
LOCATED = re.compile(r"(?P<file>[^\s:()][^:()]*\.\w+):(?P<line>\d+): (?P<message>.*)\Z", re.S)
LOCATED_AT_END = re.compile(r"(?P<message>.*) \((?P<file>[^\s:()][^:()]*\.\w+):(?P<line>\d+)\)\Z", re.S)
# Repeats a compiler error already listed with its file and line.
COMMAND_FAILED = re.compile(r"ERROR Command \S+ failed with a nonzero exit code\Z")


class Problem(Exception):
    """Why tools/check cannot tell the outcome, in words printed as they are."""


class ToolFailed(Problem):
    """An xcrun command exited with an error."""


def main(command, *args):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass
    try:
        if command == "simulator":
            return simulator(*args)
        return report(*args)
    except KeyboardInterrupt:
        return 130


def say(lines):
    for line in lines:
        print(line)


def shorten(text):
    return shorten_to(text, LONGEST_MESSAGE)


def unique(lines):
    seen = set()
    return [line for line in lines if not (line in seen or seen.add(line))]


def version_of(text, separator):
    parts = [part for part in text.split(separator) if part]
    return tuple(int(part) for part in parts) if parts and all(part.isdigit() for part in parts) else None


def dotted(version):
    return ".".join(str(part) for part in version)


def deployment_target(pbxproj):
    """The newest iOS any target deploys to: a simulator older than that cannot run the tests."""
    try:
        with open(pbxproj, encoding="utf-8", errors="replace") as handle:
            found = re.findall(r'IPHONEOS_DEPLOYMENT_TARGET = "?([0-9.]+)"?;', handle.read())
    except OSError:
        return None
    versions = [version for version in (version_of(text, ".") for text in found) if version]
    return max(versions) if versions else None


def available_devices():
    """The available simulators by runtime, each with its state ("Booted", "Shutdown", ...), as simctl lists them."""
    try:
        listing = subprocess.run(
            ["xcrun", "simctl", "list", "--json", "devices", "available"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8", errors="replace",
        )
    except OSError as error:
        raise Problem("tools/check could not run xcrun simctl: {}".format(error))
    if listing.returncode != 0:
        raise Problem("tools/check could not list the simulators: {}".format(
            first_line(listing.stderr) or "xcrun simctl exited {}".format(listing.returncode)))
    try:
        runtimes = json.loads(listing.stdout)["devices"]
        if not isinstance(runtimes, dict):
            raise TypeError
    except (ValueError, KeyError, TypeError):
        raise Problem('tools/check could not read the simulator list: xcrun simctl printed no "devices" object.')
    return runtimes


def is_booted(device, runtimes):
    return any(isinstance(found, dict) and found.get("udid") == device and found.get("state") == "Booted"
               for devices in runtimes.values() if isinstance(devices, list) for found in devices)


def simulator(pbxproj):
    """An available iPhone 17 Pro if there is one, otherwise the first available iPhone, on the newest iOS."""
    try:
        runtimes = available_devices()
    except Problem as problem:
        print(problem)
        return 2
    target = deployment_target(pbxproj)
    choices = []
    for runtime, devices in runtimes.items():
        match = re.search(r"\.iOS-([0-9-]+)\Z", runtime)
        version = version_of(match.group(1), "-") if match else None
        if version is None or (target and version < target) or not isinstance(devices, list):
            continue
        for device in devices:
            if (isinstance(device, dict) and device.get("isAvailable", True) is not False and device.get("udid")
                    and str(device.get("name", "")).startswith("iPhone")):
                choices.append((version, device))
    if not choices:
        if target:
            print("No available iPhone simulator runs iOS {} or later. Install it in Xcode > Settings > Components, "
                  "or add an iPhone in Window > Devices and Simulators.".format(dotted(target)))
        else:
            print("No iPhone simulator is available. Add one in Xcode's Window > Devices and Simulators.")
        return 2
    choices.sort(key=lambda choice: choice[0], reverse=True)
    version, device = next((choice for choice in choices if choice[1].get("name") == PREFERRED_SIMULATOR), choices[0])
    state = "booted" if device.get("state") == "Booted" else "down"
    print("{}\t{}\t{} (iOS {})".format(device["udid"], state, device["name"], dotted(version)))
    return 0


def xcresult(bundle, results, name, *command):
    """What `xcrun xcresulttool get <command>` says about the bundle, also saved as xcresult-<name>.json."""
    what = "xcresulttool get " + " ".join(command)
    try:
        run = subprocess.run(
            ["xcrun", "xcresulttool", "get"] + list(command) + ["--path", bundle],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8", errors="replace",
        )
    except OSError as error:
        raise ToolFailed("{} could not run: {}".format(what, error))
    if run.returncode != 0:
        raise ToolFailed("{} failed: {}".format(
            what, first_line(run.stderr) or first_line(run.stdout) or "exit status {}".format(run.returncode)))
    saved = os.path.join(results, "xcresult-{}.json".format(name))
    try:
        with open(saved, "w", encoding="utf-8") as handle:
            handle.write(run.stdout)
    except OSError:
        saved = "not saved"
    try:
        data = json.loads(run.stdout)
    except ValueError:
        raise Problem("{} did not print JSON ({})".format(what, saved))
    if not isinstance(data, dict):
        raise Problem("{} printed JSON that is not an object ({})".format(what, saved))
    return data


def count(summary, key, default=None):
    if key not in summary and default is not None:
        return default
    value = summary.get(key)
    if isinstance(value, bool) or not isinstance(value, int):
        raise Problem('the test summary\'s "{}" is {}, not a count'.format(key, json.dumps(value)))
    return value


def child_nodes(node, key="children", required=False):
    if required and key not in node:
        raise Problem('the test results have no "{}"'.format(key))
    nodes = node.get(key, [])
    if not isinstance(nodes, list) or not all(isinstance(child, dict) for child in nodes):
        raise Problem('"{}" in the test results is not a list of test nodes'.format(key))
    return nodes


def test_cases(nodes, bundle):
    """Each test with the name of the test bundle (target) it is in."""
    for node in nodes:
        kind = str(node.get("nodeType", ""))
        inside = str(node.get("name", "")) if kind.endswith("test bundle") else bundle
        if kind == "Test Case":
            yield inside, node
        else:
            for case in test_cases(child_nodes(node), inside):
                yield case


def failure_messages(node, arguments):
    """A test's failure messages, each with the arguments it failed with, if it takes any."""
    for child in child_nodes(node):
        kind = child.get("nodeType")
        if kind == "Failure Message":
            yield arguments, str(child.get("name") or "")
        else:
            for found in failure_messages(child, child.get("name") if kind == "Arguments" else arguments):
                yield found


def relative(path, root):
    for candidate in (path, os.path.realpath(path)):
        for base in (root, os.path.realpath(root)):
            prefix = base.rstrip("/") + "/"
            if candidate.startswith(prefix):
                return candidate[len(prefix):]
    return path


class Sources:
    """Gives a failure's file as its path in the repository, as xcresulttool names only the file."""

    def __init__(self, root):
        self.root = root
        self.paths = None

    def place(self, text):
        text = one_line(text)
        match = LOCATED.match(text) or LOCATED_AT_END.match(text)
        if not match:
            return shorten(text)
        return "{}:{}: {}".format(self.find(match.group("file")), match.group("line"), shorten(match.group("message")))

    def find(self, file):
        if os.path.isabs(file):
            return relative(file, self.root)
        if "/" in file:
            return file
        if self.paths is None:
            self.paths = {}
            for folder, folders, files in os.walk(self.root):
                folders[:] = [name for name in folders
                              if not name.startswith(".") and not os.path.splitext(name)[1]
                              and name not in ("build", "DerivedData")]
                for name in files:
                    self.paths.setdefault(name, []).append(os.path.relpath(os.path.join(folder, name), self.root))
        found = self.paths.get(file, [])
        return found[0] if len(found) == 1 else file


def failure_lines(cases, summary, failed, root):
    reasons = {}
    for entry in summary.get("testFailures") or []:
        if isinstance(entry, dict):
            test = str(entry.get("testIdentifierString") or entry.get("testName") or "an unnamed test")
            reasons.setdefault(test, []).append(str(entry.get("failureText") or "failed"))
    sources = Sources(root)
    lines = []
    for _, case in cases:
        if case.get("result") != "Failed":
            continue
        test = str(case.get("nodeIdentifier") or case.get("name") or "an unnamed test")
        found = []
        for arguments, text in failure_messages(case, None):
            label = test + (" [{}]".format(one_line(arguments)) if arguments else "")
            found.append("FAIL {}: {}".format(label, sources.place(text)))
        if not found:
            texts = reasons.get(test) or reasons.get(str(case.get("name"))) or ["failed, and the result bundle says no more"]
            found = ["FAIL {}: {}".format(test, sources.place(text)) for text in texts]
        found = unique(found)
        if len(found) > FAILURES_PER_TEST:
            found = found[:FAILURES_PER_TEST] + [
                "FAIL {}: ... and {} more failures".format(test, len(found) - FAILURES_PER_TEST)]
        lines.extend(found)
    if not lines:
        for test, texts in reasons.items():
            lines.extend("FAIL {}: {}".format(test, sources.place(text)) for text in texts)
    if not lines and failed:
        lines.append("FAIL {} tests failed, but the result bundle does not name them".format(failed))
    return lines


def source_location(url, root):
    """file:///.../Grosh/Foo.swift#...&StartingLineNumber=40 as Grosh/Foo.swift:41: the bundle counts lines from 0."""
    if not isinstance(url, str) or not url:
        return None
    parsed = urlparse(url)
    path = relative(unquote(parsed.path) if parsed.scheme == "file" else url.split("#")[0], root)
    line = (parse_qs(parsed.fragment).get("StartingLineNumber") or [""])[0]
    return "{}:{}".format(path, int(line) + 1) if line.isdigit() else path


def build_errors(build, root):
    entries = build.get("errors", [])
    if not isinstance(entries, list) or not all(isinstance(entry, dict) for entry in entries):
        raise Problem('the build results\' "errors" is not a list of issues')
    lines = []
    for entry in entries:
        where = source_location(entry.get("sourceURL"), root)
        message = shorten(one_line(entry.get("message") or entry.get("issueType") or "an unnamed error"))
        lines.append("ERROR " + (where + ": " if where else "") + message)
    lines = unique(lines)
    located = [line for line in lines if not COMMAND_FAILED.match(line)]
    lines = located or lines
    errors = build.get("errorCount")
    if not lines and isinstance(errors, int) and not isinstance(errors, bool) and errors > 0:
        lines.append("ERROR the build failed with {} errors, but the result bundle does not list them".format(errors))
    return lines


def log_hints(log, limit=5):
    """The log lines that say why xcodebuild stopped or a test trapped, for when the result bundle cannot."""
    hints = []
    try:
        with open(log, encoding="utf-8", errors="replace") as handle:
            after_testing_failed = False
            for raw in handle:
                line = raw.strip()
                if line.startswith(("xcodebuild: error:", "xcode-select: error:")) or "Fatal error:" in line:
                    hints.append(line)
                    after_testing_failed = False
                elif line.startswith("Testing failed:"):
                    after_testing_failed = True
                elif after_testing_failed and raw.startswith("\t") and line:
                    hints.append("Testing failed: " + line)
                else:
                    after_testing_failed = False
    except OSError:
        return []
    return [shorten(hint) for hint in unique(hints)[:limit]]


def crash_reports(since):
    """The Grosh app's crash reports that macOS wrote since the tests started, newest first. macOS names a report for
    the process that crashed, so other processes' reports (the Spotlight daemon's, say) are left out."""
    try:
        paths = [os.path.join(CRASH_REPORTS, name) for name in os.listdir(CRASH_REPORTS)
                 if name.startswith("Grosh-") and name.endswith(".ips")]
        fresh = [path for path in paths if os.path.getmtime(path) >= since]
        return sorted(fresh, key=os.path.getmtime, reverse=True)
    except OSError:
        return []


def crash_report_lines(path):
    """The exception and the top frames of the thread that crashed, from one .ips report: a header line, then JSON."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        report = json.loads(handle.read().partition("\n")[2])
    images = report.get("usedImages") or []
    crashed = next((thread for thread in report.get("threads") or [] if thread.get("triggered")), {})
    exception = report.get("exception") or {}
    lines = ["crash report {}: {} ({}) in {}".format(
        path, exception.get("type", "an exception"), exception.get("signal", "a signal"), report.get("procName", "?"))]
    for number, frame in enumerate((crashed.get("frames") or [])[:CRASH_FRAMES]):
        index = frame.get("imageIndex")
        image = images[index].get("name", "?") if isinstance(index, int) and 0 <= index < len(images) else "?"
        where = frame.get("symbol") or "offset {}".format(frame.get("imageOffset", "?"))
        lines.append("  {} {} {}".format(number, image, where))
    return lines


def crash_lines(log, since):
    """Why a test crashed: the runtime's Fatal error lines from the log, then the crashed thread of each new report."""
    try:
        lines = log_hints(log)
        deadline = time.monotonic() + CRASH_WAIT
        reports = crash_reports(since)
        while not reports and time.monotonic() < deadline:
            time.sleep(0.5)
            reports = crash_reports(since)
        if not reports:
            lines.append("No crash report of Grosh was written to {}.".format(CRASH_REPORTS))
        for path in reports[:CRASH_REPORTS_SHOWN]:
            lines.extend(crash_report_lines(path))
        return lines
    except Exception as error:  # the outcome stands whether or not the reports can be read
        return ["tools/check could not read the crash reports: {}: {}".format(type(error).__name__, error)]


def check_logs(root, since, ui, device):
    """Runs tools/check-logs, if it is there, for the errors Grosh logged on the simulator the tests ran on."""
    tool = os.path.join(root, "tools", "check-logs")
    if not (os.path.isfile(tool) and os.access(tool, os.X_OK)):
        return 0, []
    try:
        booted = is_booted(device, available_devices())
    except Problem:
        booted = False
    if not booted:  # check-logs reads the log of a booted simulator only
        return 0, ["tools/check-logs skipped: the simulator the tests ran on is not booted, "
                   "so there is no log to read."]
    try:
        run = subprocess.run(
            [tool, "--since", since, "--device", device] + (["--ui"] if ui else []), cwd=root,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding="utf-8", errors="replace",
        )
    except OSError as error:
        return 126, ["tools/check-logs could not run: {}".format(error)]
    return run.returncode, [line for line in run.stdout.splitlines() if line.strip()]


def report(bundle, log, status, seconds, ui, only, results, root, since, device):
    status, seconds = int(status), int(seconds)
    ui, only = ui == "1", only != "0"
    full_log, result = "Full log: " + log, "Result: " + bundle

    if not os.path.isdir(bundle):
        say(log_hints(log) + ["xcodebuild exited {} without writing a result bundle.".format(status), full_log])
        return 2
    try:
        build = xcresult(bundle, results, "build", "build-results")
        errors = build_errors(build, root)
        if errors:
            say(errors + ["0 passed, 0 failed in {}s (the build failed)".format(seconds), full_log, result])
            return 2
        try:
            summary = xcresult(bundle, results, "summary", "test-results", "summary")
        except ToolFailed as failure:
            say(log_hints(log) + ["The tests did not run: {}".format(failure), full_log, result])
            return 2
        passed, failed = count(summary, "passedTests"), count(summary, "failedTests")
        skipped, expected = count(summary, "skippedTests", 0), count(summary, "expectedFailures", 0)
        tests = xcresult(bundle, results, "tests", "test-results", "tests")
        cases = list(test_cases(child_nodes(tests, "testNodes", required=True), None))
        ran = passed + failed + expected
        if ran and not cases:
            raise Problem("the test results list no tests, though the summary counts {}".format(ran))
        lines = failure_lines(cases, summary, failed, root)
    except Problem as problem:
        say(["tools/check could not read the result bundle: {}".format(problem), full_log, result])
        return 2
    except Exception as error:
        say(["tools/check could not read the result bundle: {}: {}".format(type(error).__name__, error),
             "Its JSON is saved in " + results, full_log, result])
        return 2

    # A UI test whose app died fails only for want of its accessibility server, so its crash report is read too.
    crashed = any("crashed with signal" in line for line in lines)
    ui_failed = any(target == UI_TESTS and case.get("result") == "Failed" for target, case in cases)
    if crashed or ui_failed:
        lines.extend(crash_lines(log, int(since)))

    code = 1 if lines or failed else 0
    ui_ran = any(target == UI_TESTS for target, _ in cases)
    if not ran:
        lines.extend(log_hints(log))
        if status != 0:
            lines.append("The tests did not run: xcodebuild exited {}.".format(status))
            code = 2
        else:
            lines.append("No tests ran." + (" Check the names given to --only." if only else ""))
            code = 1
    elif ui and not only and not ui_ran:
        lines.append("{} did not run, though --ui asked for it (see docs/agents/testing.md).".format(UI_TESTS))
        code = 1
    if code == 0 and (status != 0 or summary.get("result") == "Failed"):
        lines.extend(log_hints(log))
        lines.append("xcodebuild exited {}, though the result bundle shows no failed test.".format(status))
        code = 1

    note = ""
    if ran:
        logged_status, logged = check_logs(root, since, ui_ran, device)
        lines.extend(logged)
        if logged_status:
            code = max(code, 1)
            note = ("; Grosh logged errors (tools/check-logs)" if logged_status == 1
                    else "; tools/check-logs exited {}".format(logged_status))

    counts = "{} passed".format(passed) if code == 0 else "{} passed, {} failed".format(passed, failed)
    said = "{} in {}s".format(counts, seconds) + (" ({} skipped)".format(skipped) if skipped else "") + note
    say(lines + [said] + ([full_log, result] if code else [result]))
    return code


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
