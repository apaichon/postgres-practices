"""Read-only CLI/plan tests. Run with python3 -m unittest discover -s runner."""
import importlib.util
import os
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("continuous_runner", ROOT / "runner/main.py")
runner = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = runner
spec.loader.exec_module(runner)


class PlanTests(unittest.TestCase):
    def steps(self, module):
        return runner.build_steps(module, runner.Guide(module))

    def test_whole_course_keeps_core_data_for_later_modules(self):
        for module in runner.MODULES:
            plan = runner.select_steps(self.steps(module), [])
            self.assertTrue(plan)
            self.assertFalse(any(s.instructor for s in plan))
            self.assertFalse(any(s.id in ("1Z", "2Z", "10G") for s in plan))

    def test_backup_group_includes_checks_and_restore_in_order(self):
        selected = runner.select_steps(self.steps(7), ["7.2"])
        self.assertEqual([s.id for s in selected], ["7.2" + c for c in "abcdefghi"])
        self.assertEqual(selected[4].requires, ("7.2d",))

    def test_selectors_do_not_confuse_a_step_with_another_group(self):
        selected = runner.select_steps(self.steps(7), ["7.4b"])
        self.assertEqual([s.id for s in selected], ["7.4b"])
        with self.assertRaises(runner.LabError):
            runner.select_steps(self.steps(7), ["7.40"])

    def test_broad_prefix_cannot_enable_external_or_destructive_steps(self):
        for module in (1, 2, 10):
            with self.assertRaises(runner.LabError):
                runner.select_steps(self.steps(module), [str(module)])

    def test_private_wal_group_and_reversed_input(self):
        self.assertEqual([s.id for s in runner.select_steps(self.steps(6), ["6D"])], ["6D.1", "6D.2", "6D.3", "6D.4"])
        self.assertEqual([s.id for s in runner.select_steps(self.steps(1), ["1B", "1A"])], ["1A", "1B"])

    def test_expected_errors_are_specific(self):
        four = {s.id: s for s in self.steps(4)}
        self.assertEqual(four["4B"].actions[0][-1], ("42501", "42501"))
        six = {s.id: s for s in self.steps(6)}
        self.assertEqual(six["6C"].actions[0][-1], ("57014",))
        self.assertEqual(six["6C"].actions[1][-1], ("55P03",))

    def test_every_referenced_block_exists(self):
        for module in runner.MODULES:
            guide = runner.Guide(module)
            for step in self.steps(module):
                for action in step.actions:
                    if action[0] in ("sql", "bash"):
                        self.assertTrue(guide.block(action[1], "sql" if action[0] == "sql" else "bash", action[2]))

    def test_list_show_and_check_do_not_need_postgres(self):
        for command in (("list", "7"), ("show", "7", "7.4b"), ("check", "all")):
            r = subprocess.run([sys.executable, str(ROOT / "runner/main.py"), *command], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_invalid_module_or_student_is_rejected_before_connecting(self):
        for args in (("run", "8"), ("run", "1", "--student", "../01"), ("show", "7", "D2")):
            r = subprocess.run([sys.executable, str(ROOT / "runner/main.py"), *args], capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("STOP:", r.stderr)

    def test_execution_requires_an_assigned_number_instead_of_defaulting(self):
        env = {**os.environ, "STUDENT_NO": "", "PGPASSWORD": ""}
        for args in (("run", "1"), ("status", "1"), ("run", "1", "--student", "xx")):
            r = subprocess.run([sys.executable, str(ROOT / "runner/main.py"), *args],
                               env=env, capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("STOP:", r.stderr)
            self.assertNotIn("password", r.stderr.lower())

    def test_security_roles_follow_the_current_login(self):
        sql = runner.Guide(4).block("4B")
        self.assertIn('SET LOCAL ROLE :"actor_role";', sql)
        self.assertIn('TO :"reader_role";', sql)
        self.assertNotIn("cs_actor_", sql)

    def test_backup_runner_uses_the_native_guide(self):
        self.assertEqual(runner.Guide(7).path.name, "module-07-backup-recovery.md")


if __name__ == "__main__":
    unittest.main()
