import csv
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from approval_audit import approval_rows, collect_offline, write_reports  # noqa: E402


class ApprovalAuditTests(unittest.TestCase):
    def test_offline_fixture_contains_pr_and_deployment_approver(self):
        data = collect_offline(ROOT / "audit" / "fixtures")
        rows = approval_rows(data)
        self.assertEqual([row["approver"] for row in rows], ["reviewer", "release-manager"])

    def test_reports_write_markdown_and_csv(self):
        data = collect_offline(ROOT / "audit" / "fixtures")
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory) / "audit"
            write_reports(approval_rows(data), prefix)
            self.assertIn("release-manager", prefix.with_suffix(".md").read_text())
            with prefix.with_suffix(".csv").open(newline="") as handle:
                self.assertEqual(len(list(csv.DictReader(handle))), 2)


if __name__ == "__main__":
    unittest.main()
