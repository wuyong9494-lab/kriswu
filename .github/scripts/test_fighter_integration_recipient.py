import base64
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location("recipient", Path(__file__).with_name("fighter_integration_recipient.py"))
recipient = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recipient)


class RecipientScopeTests(unittest.TestCase):
    def event(self):
        head = "a" * 40
        env = dict(GITHUB_REPOSITORY=recipient.REPOSITORY, GITHUB_REF=recipient.BRANCH,
            GITHUB_EVENT_NAME="push", GITHUB_RUN_ATTEMPT="1", GITHUB_SHA=head, GITHUB_WORKFLOW_SHA=head,
            GITHUB_WORKFLOW_REF=recipient.REPOSITORY + "/" + recipient.WORKFLOW + "@" + recipient.BRANCH)
        event = dict(before=recipient.PARENT, after=head, ref=recipient.BRANCH, deleted=False, forced=False,
            repository=dict(full_name=recipient.REPOSITORY), commits=[dict(id=head)],
            head_commit=dict(id=head, message=recipient.TITLE))
        return env, event, head

    def test_exact_push_only(self):
        env, event, head = self.event()
        recipient.validate_event(env, event, head, [recipient.PARENT], recipient.TITLE, recipient.ALLOWED)
        for key, bad in (("GITHUB_RUN_ATTEMPT", "2"), ("GITHUB_EVENT_NAME", "pull_request"),
                         ("GITHUB_SHA", "b" * 40), ("GITHUB_REPOSITORY", "unrelated/repo")):
            with self.assertRaises(ValueError):
                recipient.validate_event(dict(env, **{key: bad}), event, head, [recipient.PARENT], recipient.TITLE, recipient.ALLOWED)
        for key, bad in (("forced", True), ("deleted", True), ("before", "b" * 40), ("commits", [])):
            with self.assertRaises(ValueError):
                recipient.validate_event(env, dict(event, **{key: bad}), head, [recipient.PARENT], recipient.TITLE, recipient.ALLOWED)

    def test_app_change_extra_parent_and_other_title_rejected(self):
        env, event, head = self.event()
        for parents, title, changed in (([recipient.PARENT], recipient.TITLE, recipient.ALLOWED | {"App/Game.swift"}),
                ([recipient.PARENT, "b" * 40], recipient.TITLE, recipient.ALLOWED),
                ([recipient.PARENT], "other", recipient.ALLOWED)):
            with self.assertRaises(ValueError):
                recipient.validate_event(env, event, head, parents, title, changed)

    def test_existing_key_requires_exact_32_bytes_and_authentication_is_bound(self):
        key = bytes(range(32))
        self.assertEqual(recipient.resource_key(base64.b64encode(key).decode()), key)
        for text in (None, "", "notbase64", base64.b64encode(key[:-1]).decode()):
            with self.assertRaises(ValueError): recipient.resource_key(text)
        original = recipient.wrapper_hmac(key, b"encrypted PKCS8")
        self.assertNotEqual(original, recipient.wrapper_hmac(key, b"different encrypted PKCS8"))
        self.assertNotEqual(original, recipient.wrapper_hmac(bytes(reversed(key)), b"encrypted PKCS8"))

    def test_subprocesses_do_not_inherit_credentials(self):
        with mock.patch.dict(os.environ, {recipient.KEY_NAME: "never-forward", "GITHUB_TOKEN": "never-forward", "PATH": "/usr/bin"}), \
             mock.patch.object(recipient.subprocess, "run") as call:
            call.return_value.returncode = 0; call.return_value.stdout = b"ok"
            self.assertEqual(recipient.run(["test"]), b"ok")
            env = call.call_args.kwargs["env"]
            self.assertNotIn(recipient.KEY_NAME, env); self.assertNotIn("GITHUB_TOKEN", env)
            self.assertEqual(env["PATH"], "/usr/bin")

    def test_duplicate_json_symlink_and_oversized_inputs_rejected(self):
        with self.assertRaises(ValueError): recipient.unique_json(b'{"x":1,"x":2}')
        with self.assertRaises(ValueError): recipient.unique_json(b'{"x":NaN}')
        with tempfile.TemporaryDirectory() as name:
            base = Path(name).resolve(strict=True)
            file = base / "file"; file.write_bytes(b"content")
            alias = base / "alias"; alias.symlink_to(file)
            with self.assertRaises(ValueError): recipient.regular(alias)
            with self.assertRaises(ValueError): recipient.regular(file, 2)

    def test_cleanup_keeps_only_encrypted_outputs(self):
        with tempfile.TemporaryDirectory() as name:
            base = Path(name).resolve(strict=True)
            (base / "private").mkdir(); (base / "private/key.pem").write_bytes(b"test key")
            (base / "published").mkdir()
            for value in recipient.PUBLIC_NAMES: (base / "published" / value).write_bytes(b"test")
            with mock.patch.object(recipient, "work", return_value=base): recipient.cleanup()
            self.assertFalse((base / "private").exists())
            self.assertEqual({p.name for p in (base / "published").iterdir()}, recipient.PUBLIC_NAMES)


if __name__ == "__main__":
    unittest.main()
