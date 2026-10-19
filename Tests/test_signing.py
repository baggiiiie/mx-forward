import importlib.util
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("signing", Path(__file__).resolve().parents[1] / "scripts/signing.py")
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class SigningTests(unittest.TestCase):
    first = signing.Identity("A" * 40, "Local Development")
    second = signing.Identity("B" * 40, "Other Certificate")

    def test_selects_the_only_valid_identity(self):
        self.assertEqual(signing.select_identity([self.first]), self.first)

    def test_saved_fingerprint_wins_over_new_certificates(self):
        self.assertEqual(signing.select_identity([self.first, self.second], saved=self.first.fingerprint), self.first)

    def test_explicit_selection_can_use_name_or_fingerprint(self):
        self.assertEqual(signing.select_identity([self.first, self.second], explicit=self.second.name), self.second)
        self.assertEqual(signing.select_identity([self.first], explicit=self.first.fingerprint.lower()), self.first)

    def test_missing_saved_certificate_does_not_silently_change_identity(self):
        with self.assertRaises(signing.SigningError):
            signing.select_identity([self.second], saved=self.first.fingerprint)

    def test_ad_hoc_missing_and_ambiguous_choices_are_rejected(self):
        for identities, choice in [([], None), ([self.first, self.second], None), ([self.first], "-")]:
            with self.subTest(choice=choice), self.assertRaises(signing.SigningError):
                signing.select_identity(identities, explicit=choice)

    def test_certificate_is_pinned_not_binary_hash(self):
        rule = signing.requirement("local.baggie.mxforward.agent", self.first.fingerprint)
        self.assertIn('certificate leaf = H"', rule)
        self.assertNotIn("cdhash", rule)
        with self.assertRaises(signing.SigningError):
            signing.requirement('bad"identifier', self.first.fingerprint)

    def test_choice_is_saved_privately_and_reused(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(signing.Path, "home", return_value=Path(directory)), \
             patch.dict(os.environ, {}, clear=True), \
             patch.object(signing, "available_identities", return_value=[self.first]) as available:
            self.assertEqual(signing.resolve_identity(), self.first)
            cache = Path(directory) / ".config/mx-forward/signing-identity"
            self.assertEqual(cache.read_text().strip(), self.first.fingerprint)
            self.assertEqual(stat.S_IMODE(cache.stat().st_mode), 0o600)
            available.return_value = [self.second, self.first]
            self.assertEqual(signing.resolve_identity(), self.first)
            available.return_value = [self.second]
            with self.assertRaises(signing.SigningError):
                signing.resolve_identity()
            self.assertEqual(cache.read_text().strip(), self.first.fingerprint)


if __name__ == "__main__":
    unittest.main()
