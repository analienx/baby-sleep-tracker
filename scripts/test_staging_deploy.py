"""Offline tests for the Spark staging deployment CLI.

No GitHub credential, Firebase project, or Android phone is needed.
"""
import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, main
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "staging_deploy", Path(__file__).with_name("staging_deploy.py")
)
app = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(app)


class DeploymentTests(TestCase):
    @patch.object(app, "gh_json")
    def test_accept_only_successful_staging_run(self, gh):
        good = {
            "status": "completed", "conclusion": "success",
            "headSha": "a" * 40, "headBranch": app.BRANCH,
            "workflowName": "Spark staging Android", "url": "https://github.com/test",
        }
        gh.return_value = good
        self.assertEqual(app.checked_run(41), good)
        # Family Lite can only reuse an artifact built from the explicitly
        # selected reviewed feature branch, never from another branch.
        family = {**good, "headBranch": "feat/spark-family-lite"}
        gh.return_value = family
        self.assertEqual(
            app.checked_run(42, "feat/spark-family-lite"), family
        )
        with self.assertRaises(app.Blocked):
            app.checked_run(42)
        gh.return_value = good
        for change in ({"conclusion": "skipped"}, {"headBranch": "main"},
                       {"workflowName": "Flutter CI"}, {"status": "in_progress"}):
            gh.return_value = {**good, **change}
            with self.assertRaises(app.Blocked):
                app.checked_run(41)

    @patch.object(app, "gh_json")
    @patch.object(app, "call")
    @patch("shutil.which", return_value="/usr/bin/gh")
    def test_readiness_checks_names_not_contents(self, which, call, gh):
        gh.side_effect = [[], []]
        self.assertFalse(app.doctor())
        self.assertTrue(any("secret" in args for args, _ in gh.call_args_list))
        # No secret mutation, only list operations, until operator runs configure.
        self.assertFalse(any(
            x.args[:3] == ("gh", "secret", "set") for x in call.call_args_list
        ))

    @patch.object(app, "checked_run", return_value={"url": "https://example"})
    @patch.object(app, "aapt", return_value=None)
    @patch.object(app, "adb_one", return_value="dummy")
    @patch.object(app, "present", side_effect=[True, True, True])
    @patch.object(app, "call", side_effect=lambda *args: (
        f"{app.PKG}/com.analienx.baby_sleep_tracker.MainActivity"
        if "resolve-activity" in args else ""))
    def test_preserves_preview_and_only_installs(self, call, *_):
        with TemporaryDirectory() as tmp:
            file = Path(tmp) / "app-debug.apk"
            file.write_bytes(b"synthetic")
            app.install(file, 42)
        self.assertFalse(any("uninstall" in a.args for a in call.call_args_list))
        self.assertTrue(any("install" in a.args for a in call.call_args_list))
        # Application ID has .staging, but Kotlin activity namespace remains unsuffixed.
        launch = [a.args for a in call.call_args_list if "am" in a.args]
        self.assertEqual(len(launch), 1)
        self.assertEqual(launch[0][-1],
                         f"{app.PKG}/com.analienx.baby_sleep_tracker.MainActivity")

    @patch.object(app, "checked_run", return_value={"url": "https://example"})
    @patch.object(app, "aapt", return_value=None)
    @patch.object(app, "adb_one", return_value="dummy")
    @patch.object(app, "present", return_value=False)
    @patch.object(app, "call", return_value="")
    def test_missing_preview_fails_closed(self, call, *_):
        with TemporaryDirectory() as tmp:
            file = Path(tmp) / "app-debug.apk"
            file.write_bytes(b"synthetic")
            with self.assertRaises(app.Blocked):
                app.install(file, 42)
        self.assertFalse(any("install" in a.args for a in call.call_args_list))


if __name__ == "__main__":
    main()
