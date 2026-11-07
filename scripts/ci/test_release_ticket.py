import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release_ticket', Path(__file__).resolve().parents[1] / 'release-ticket.py')
ticket = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ticket)


class ReleaseTicketTests(unittest.TestCase):
    def exercise(self, operation, results):
        with patch.object(ticket.subprocess, 'run', side_effect=results) as run, patch.object(ticket.time, 'sleep') as sleep:
            code = ticket.run_stapler(operation, '/tmp/Job’s Done.app')
        for call in run.call_args_list:
            self.assertEqual(call.args[0], ['xcrun', 'stapler', operation, '/tmp/Job’s Done.app'])
            self.assertEqual(call.kwargs['timeout'], 120)
        return code, run.call_count, [call.args[0] for call in sleep.call_args_list]

    def result(self, code):
        return subprocess.CompletedProcess([], code)

    def test_success_needs_no_retry(self):
        self.assertEqual(self.exercise('staple', [self.result(0)]), (0, 1, []))

    def test_stapling_and_validation_recover_without_rebuilding(self):
        for operation in ('staple', 'validate'):
            with self.subTest(operation=operation):
                self.assertEqual(self.exercise(operation, [self.result(68), self.result(65), self.result(0)]), (0, 3, [30, 60]))

    def test_persistent_ticket_failure_stops_after_three_attempts(self):
        for code in (65, 68):
            self.assertEqual(self.exercise('validate', [self.result(code)] * 3), (code, 3, [30, 60]))

    def test_other_failures_stop_immediately(self):
        self.assertEqual(self.exercise('staple', [self.result(1)]), (1, 1, []))

    def test_timeout_is_bounded_and_retried(self):
        timeout = subprocess.TimeoutExpired('xcrun', 120)
        self.assertEqual(self.exercise('validate', [timeout, self.result(0)]), (0, 2, [30]))
        self.assertEqual(self.exercise('validate', [timeout] * 3), (124, 3, [30, 60]))


if __name__ == '__main__':
    unittest.main()
