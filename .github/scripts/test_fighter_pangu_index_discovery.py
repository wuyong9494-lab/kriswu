"""Only synthetic/offline tests for the one-request CI diagnostic."""
import contextlib
import copy
import email.message
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import types
import unittest
from unittest import mock
import urllib.error
import zipfile

import fighter_pangu_index_discovery as subject


class Response(io.BytesIO):
    def __init__(self, data=b"", status=200, headers=None):
        super().__init__(data)
        self.status = status
        self.headers = email.message.Message()
        for key, value in (headers or {}).items():
            self.headers[key] = value
        self.read_calls = 0

    def read(self, amount=-1):
        self.read_calls += 1
        return super().read(amount)


def opener(response=None, error=None):
    result = mock.Mock()
    result.addheaders = [("User-agent", "Python-urllib/test")]
    result.open = mock.Mock(return_value=response, side_effect=error)
    return result


def event_fixture():
    source = "a" * 40
    env = dict(GITHUB_ACTIONS="true", RUNNER_OS="Linux", GITHUB_REPOSITORY=subject.REPOSITORY,
               GITHUB_REF=subject.REF, GITHUB_EVENT_NAME="push", GITHUB_RUN_ATTEMPT="1",
               GITHUB_SHA=source, GITHUB_WORKFLOW_SHA=source, GITHUB_RUN_ID="12345",
               GITHUB_WORKFLOW_REF=subject.REPOSITORY + "/" + subject.WORKFLOW + "@" + subject.REF)
    event = dict(ref=subject.REF, repository=dict(full_name=subject.REPOSITORY),
                 head_commit=dict(id=source, message=subject.MESSAGE))
    return env, event, source


class BootstrapDiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.real_deadline = subject.network_deadline
        self.timer = mock.patch.object(subject, "network_deadline", side_effect=lambda: contextlib.nullcontext())
        self.timer.start()
        self.addCleanup(self.timer.stop)

    def test_exact_source_push_is_admitted_and_wrong_identity_or_rerun_is_rejected(self):
        env, event, source = event_fixture()
        subject.validate_event(env, event, source)
        for key, value in [("GITHUB_RUN_ATTEMPT", "2"), ("GITHUB_SHA", "b" * 40),
                           ("GITHUB_WORKFLOW_SHA", "b" * 40), ("GITHUB_REF", "refs/heads/main"),
                           ("GITHUB_REPOSITORY", "other/repo"), ("GITHUB_EVENT_NAME", "pull_request"),
                           ("GITHUB_WORKFLOW_REF", "other/workflow"), ("RUNNER_OS", "Windows")]:
            with self.subTest(key=key), self.assertRaises(subject.GuardError):
                subject.validate_event({**env, key: value}, event, source)
        for key, value in [("id", "b" * 40), ("message", "unreviewed request")]:
            wrong = copy.deepcopy(event)
            wrong["head_commit"][key] = value
            with self.assertRaises(subject.GuardError):
                subject.validate_event(env, wrong, source)

    def test_resource_key_environment_is_rejected_even_if_empty(self):
        subject.no_resource_keys({"GITHUB_TOKEN": "synthetic"})
        for key in ["FIGHTER_LIU_MODEL_KEY", "FIGHTER_PRESENTATION_KEY", "FIGHTER_H17_D19_KEY"]:
            with self.subTest(key=key), self.assertRaises(subject.GuardError):
                subject.no_resource_keys({key: ""})

    def test_source_files_must_match_the_event_commit_before_crypto_or_network(self):
        env, event, source = event_fixture()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            names = (subject.WORKFLOW, subject.SCRIPT, subject.TEST, *subject.DEPENDENCY_PINS)
            rows = []
            for name in names:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"synthetic-source")
                digest = hashlib.sha1(b"blob 16\0synthetic-source").hexdigest()
                rows.append(b"100644 blob " + digest.encode() + b"\t" + name.encode() + b"\0")
            (root / subject.SCRIPT).write_bytes(b"dirty-source")
            event_path = root / "event.json"
            event_path.write_text(json.dumps(event))
            env["GITHUB_EVENT_PATH"] = str(event_path)
            with mock.patch.object(subject, "ROOT", root), mock.patch.dict(os.environ, env, clear=True), \
                    mock.patch.object(subject.subprocess, "check_output", side_effect=[source + "\n", b"".join(rows)]), \
                    mock.patch.object(subject, "public_digest") as crypto, \
                    mock.patch.object(subject.urllib.request, "build_opener") as network:
                with self.assertRaisesRegex(subject.GuardError, "differs from admitted commit"):
                    subject.source_identity()
            crypto.assert_not_called()
            network.assert_not_called()

    def test_total_deadline_is_armed_once_and_restored_on_exception(self):
        with mock.patch.object(subject.signal, "getsignal", return_value="previous"), \
                mock.patch.object(subject.signal, "getitimer", return_value=(0.0, 0.0)), \
                mock.patch.object(subject.signal, "signal") as handler, \
                mock.patch.object(subject.signal, "setitimer") as timer:
            with self.assertRaises(RuntimeError):
                with self.real_deadline():
                    raise RuntimeError("synthetic timeout path")
            self.assertEqual(timer.call_args_list, [mock.call(subject.signal.ITIMER_REAL, 20),
                                                    mock.call(subject.signal.ITIMER_REAL, 0)])
            self.assertEqual(handler.call_args_list[-1], mock.call(subject.signal.SIGALRM, "previous"))

    def test_default_proxy_and_tls_handlers_are_retained(self):
        response = Response(b"{}")
        fake = opener(response)
        with mock.patch.object(subject.urllib.request, "build_opener", return_value=fake) as build:
            receipt, data = subject.capture_http()
        self.assertEqual(build.call_count, 1)
        self.assertEqual(len(build.call_args.args), 1)
        self.assertIsInstance(build.call_args.args[0], subject.NoRedirect)
        request = fake.open.call_args.args[0]
        self.assertEqual(request.full_url, subject.REQUEST_URL)
        self.assertEqual(request.get_method(), "GET")
        self.assertIsNone(request.data)
        self.assertEqual(request.header_items(), [])
        self.assertEqual(fake.open.call_args.kwargs, {"timeout": 20})
        self.assertEqual(receipt["requestCount"], 1)
        self.assertEqual(receipt["subsequentURLsFetched"], 0)
        self.assertTrue(response.closed)

    def test_400_body_is_captured_once_but_is_not_recovered(self):
        data = b"Failure: 400 Bad Request\r\n"
        error = urllib.error.HTTPError(subject.REQUEST_URL, 400, "Bad Request",
                                       email.message.Message(), io.BytesIO(data))
        fake = opener(error=error)
        receipt, body = subject.capture_http(fake)
        fake.open.assert_called_once()
        self.assertEqual(body, data)
        self.assertEqual(receipt["completeBodySHA256"], subject.OLD_BODY_SHA)
        self.assertEqual(receipt["classification"], "http-failure")
        self.assertTrue(receipt["matchesPrior26ByteFailure"])
        self.assertFalse(receipt["D19Recovered"])

    def test_redirect_is_refused_and_location_is_never_requested(self):
        policy = subject.NoRedirect()
        self.assertIsNone(policy.redirect_request(None, None, 302, "Found", {}, "https://other.example/private"))
        response = Response(b"redirect", status=302, headers={"Location": "https://other.example/private"})
        fake = opener(response)
        receipt, _ = subject.capture_http(fake)
        fake.open.assert_called_once()
        self.assertEqual(receipt["classification"], "http-failure")
        self.assertEqual(receipt["redirects"], 0)

    def test_declared_oversize_is_closed_without_reading_body(self):
        response = Response(b"not read", headers={"Content-Length": str(subject.MAX_BODY + 1)})
        receipt, data = subject.capture_http(opener(response))
        self.assertEqual(response.read_calls, 0)
        self.assertTrue(response.closed)
        self.assertEqual(data, b"")
        self.assertFalse(receipt["bodyComplete"])
        self.assertIsNone(receipt["completeBodySHA256"])
        self.assertEqual(receipt["boundedStop"], "declared-body-over-cap")

    def test_stream_limit_reads_only_one_extra_byte_and_labels_partial_hash(self):
        response = Response(b"x" * (subject.MAX_BODY + 100))
        receipt, data = subject.capture_http(opener(response))
        self.assertEqual(len(data), subject.MAX_BODY)
        self.assertEqual(receipt["bodyBytesRead"], subject.MAX_BODY + 1)
        self.assertIsNone(receipt["completeBodySHA256"])
        self.assertEqual(receipt["classification"], "incomplete-response")
        self.assertTrue(response.closed)

    def test_large_headers_and_truncated_body_fail_closed(self):
        response = Response(b"unread", headers={"X-Large": "x" * subject.MAX_HEADERS})
        receipt, _ = subject.capture_http(opener(response))
        self.assertEqual(response.read_calls, 0)
        self.assertEqual(receipt["boundedStop"], "headers-over-cap")
        response = Response(b"short", headers={"Content-Length": "10"})
        receipt, _ = subject.capture_http(opener(response))
        self.assertEqual(receipt["boundedStop"], "declared-body-truncated")
        self.assertFalse(receipt["bodyComplete"])

    def test_timeout_is_not_retried_or_printed(self):
        fake = opener(error=subject.RequestDeadline("PRIVATE_EXCEPTION_SENTINEL"))
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            receipt, data = subject.capture_http(fake)
        fake.open.assert_called_once()
        self.assertEqual(data, b"")
        self.assertEqual(receipt["classification"], "transport-failure")
        self.assertNotIn("PRIVATE_EXCEPTION_SENTINEL", json.dumps(receipt) + output.getvalue())

    def test_explicit_denial_marker_stops_as_policy_denied(self):
        response = Response(b"Destination denied by network policy", status=403)
        fake = opener(response)
        receipt, _ = subject.capture_http(fake)
        self.assertEqual(receipt["classification"], "policy-denied")
        self.assertTrue(receipt["explicitPolicyDenialMarker"])
        fake.open.assert_called_once()
        header_only = Response(b"refused", status=403, headers={"X-Reason": "Destination denied"})
        receipt, _ = subject.capture_http(opener(header_only))
        self.assertEqual(receipt["classification"], "policy-denied")

    def test_json_url_is_only_a_candidate_and_is_never_followed(self):
        value = {"bundles": {"url": "https://sf3assets.nekki.com/private-actual-index"}}
        fake = opener(Response(json.dumps(value).encode()))
        receipt, _ = subject.capture_http(fake)
        fake.open.assert_called_once()
        self.assertEqual(receipt["classification"], "bootstrap-locator-candidate")
        self.assertTrue(receipt["locatorCandidate"])
        self.assertFalse(receipt["D19Recovered"])
        result = subject.public_report(receipt, dict(sourceSHA="a" * 40, runID="123", attempt=1), True)
        self.assertNotIn("private-actual-index", json.dumps(result))
        self.assertFalse(result["D19Recovered"])
        self.assertEqual(result["newD19MotionFiles"], 0)

    def test_non_locator_duplicate_json_or_encoded_content_is_not_success(self):
        cases = [(b"{}", {}, "json-without-locator"),
                 (b'{"bundles":{},"bundles":{}}', {}, "non-json-response"),
                 (b"[]", {}, "non-object-response"),
                 (b"{}", {"Content-Encoding": "gzip"}, "unsupported-content-encoding")]
        for body, headers, expected in cases:
            with self.subTest(expected=expected):
                receipt, _ = subject.capture_http(opener(Response(body, headers=headers)))
                self.assertEqual(receipt["classification"], expected)
                report = subject.public_report(receipt, dict(sourceSHA="a" * 40, runID="123", attempt=1), True)
                self.assertEqual(report["result"], "unrecovered")

    def test_private_output_rejects_checkout_symlink_and_traversal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "repo").mkdir()
            (root / "repo" / "temp").mkdir()
            (root / "linked").symlink_to(root / "repo", target_is_directory=True)
            for candidate in [root / "repo" / "temp", root / "linked", root / "repo" / ".."]:
                with mock.patch.object(subject, "ROOT", root / "repo"), mock.patch.dict(os.environ, {"RUNNER_TEMP": str(candidate)}):
                    with self.assertRaises(subject.GuardError):
                        subject.directory()

    def test_repeated_capture_rejects_before_network_and_preserves_receipt(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            subject.claim_once(path)
            before = (path / "request-started.json").read_bytes()
            with mock.patch.object(subject, "identity", return_value={}), mock.patch.object(subject, "directory", return_value=path), \
                    mock.patch.object(subject, "capture_http") as network:
                with self.assertRaises(FileExistsError):
                    subject.capture()
            network.assert_not_called()
            self.assertEqual(before, (path / "request-started.json").read_bytes())
            self.assertEqual(stat.S_IMODE((path / "request-started.json").stat().st_mode), 0o600)

    def test_authentication_and_published_set_only_use_fresh_diagnostic_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            saved = dict(sourceSHA="a" * 40, runID="123", attempt=1)
            receipt, body = subject.capture_http(opener(Response(b"PRIVATE_RESPONSE_SENTINEL", status=400)))
            receipt.update(saved)
            subject.write_json(path / "identity.json", saved)
            subject.claim_once(path)
            subject.write_json(path / "receipt.json", receipt)
            subject.write_new(path / "response.bin", body)
            calls = []
            def wrap(key, public, destination):
                calls.append(key)
                subject.write_new(destination, b"synthetic-wrapped-key")
            def seal_archive(source, destination):
                self.assertEqual(os.environ["FIGHTER_LIU_MODEL_KEY"], "11" * 32)
                with zipfile.ZipFile(source) as archive:
                    self.assertEqual(set(archive.namelist()), set(subject.PRIVATE_NAMES[:4]))
                    self.assertEqual(archive.read("response.bin"), body)
                subject.write_new(destination, b"synthetic-authenticated-ciphertext")
            module = types.SimpleNamespace(seal_evidence_file=seal_archive)
            loader = mock.Mock()
            spec = types.SimpleNamespace(loader=loader)
            output = io.StringIO()
            with mock.patch.object(subject, "identity", return_value=saved), mock.patch.object(subject, "directory", return_value=path), \
                    mock.patch.object(subject, "wrap_key", side_effect=wrap), \
                    mock.patch.object(subject, "existing_recipient", return_value=b"synthetic-public"), \
                    mock.patch.object(subject.secrets, "token_bytes", return_value=b"\x11" * 32), \
                    mock.patch.object(subject.importlib.util, "spec_from_file_location", return_value=spec), \
                    mock.patch.object(subject.importlib.util, "module_from_spec", return_value=module), \
                    mock.patch.dict(os.environ, {}, clear=True), contextlib.redirect_stdout(output):
                subject.seal()
                self.assertNotIn("FIGHTER_LIU_MODEL_KEY", os.environ)
            self.assertEqual(calls, [b"\x11" * 32, b"\x11" * 32])
            self.assertEqual({p.name for p in (path / "published").iterdir()}, set(subject.UPLOAD_NAMES))
            self.assertTrue(subject.published_complete(path / "published"))
            self.assertFalse((path / "private-evidence.zip").exists())
            self.assertNotIn("PRIVATE_RESPONSE_SENTINEL", output.getvalue())
            self.assertTrue(all(stat.S_IMODE(p.stat().st_mode) == 0o600 for p in (path / "published").iterdir()))
            (path / "published" / subject.CIPHER_NAMES[0]).write_bytes(b"tampered")
            self.assertFalse(subject.published_complete(path / "published"))

    def test_sealing_failure_cannot_publish_partial_keys_or_keep_fresh_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            for name in subject.PRIVATE_NAMES[:4]:
                subject.write_new(path / name, b"synthetic")
            with mock.patch.object(subject, "identity", return_value={}), mock.patch.object(subject, "directory", return_value=path), \
                    mock.patch.object(subject, "validated_capture"), mock.patch.object(subject, "existing_recipient", return_value=b"synthetic"), \
                    mock.patch.object(subject, "wrap_key", side_effect=RuntimeError("PRIVATE_FAILURE")), \
                    mock.patch.dict(os.environ, {}, clear=True):
                with self.assertRaises(RuntimeError):
                    subject.seal()
                self.assertNotIn("FIGHTER_LIU_MODEL_KEY", os.environ)
            self.assertFalse((path / "published").exists())
            self.assertFalse((path / "private-evidence.zip").exists())

    def test_envelope_failure_clears_in_process_diagnostic_key_and_partial_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            for name in subject.PRIVATE_NAMES[:4]:
                subject.write_new(path / name, b"synthetic")
            def wrap(key, public, destination):
                subject.write_new(destination, b"synthetic-wrapped-key")
            def fail(source, destination):
                self.assertEqual(os.environ["FIGHTER_LIU_MODEL_KEY"], "22" * 32)
                raise RuntimeError("synthetic seal failure")
            module = types.SimpleNamespace(seal_evidence_file=fail)
            spec = types.SimpleNamespace(loader=mock.Mock())
            with mock.patch.object(subject, "identity", return_value={}), mock.patch.object(subject, "directory", return_value=path), \
                    mock.patch.object(subject, "validated_capture"), mock.patch.object(subject, "existing_recipient", return_value=b"synthetic"), \
                    mock.patch.object(subject, "wrap_key", side_effect=wrap), \
                    mock.patch.object(subject.secrets, "token_bytes", return_value=b"\x22" * 32), \
                    mock.patch.object(subject.importlib.util, "spec_from_file_location", return_value=spec), \
                    mock.patch.object(subject.importlib.util, "module_from_spec", return_value=module), \
                    mock.patch.dict(os.environ, {}, clear=True):
                with self.assertRaises(RuntimeError):
                    subject.seal()
                self.assertNotIn("FIGHTER_LIU_MODEL_KEY", os.environ)
            self.assertFalse((path / "published").exists())
            self.assertFalse((path / "private-evidence.zip").exists())

    def test_source_workflow_has_no_secrets_native_jobs_or_broad_upload(self):
        workflow = (subject.ROOT / subject.WORKFLOW).read_text()
        self.assertNotIn("secrets.", workflow)
        self.assertNotIn("environment:", workflow)
        self.assertNotIn("workflow_dispatch", workflow)
        self.assertNotIn("xcodebuild", workflow)
        self.assertNotIn("swift test", workflow)
        self.assertNotIn("cancel-in-progress: true", workflow)
        self.assertIn("runs-on: ubuntu-24.04", workflow)
        self.assertIn("timeout-minutes: 5", workflow)
        self.assertIn("retention-days: 3", workflow)
        self.assertIn("persist-credentials: false", workflow)
        upload = workflow.split("path: |", 1)[1].split("if-no-files-found:", 1)[0]
        lines = [line.strip() for line in upload.splitlines() if line.strip()]
        self.assertEqual(len(lines), 4)
        self.assertEqual({line.rsplit("/", 1)[1] for line in lines}, set(subject.UPLOAD_NAMES))
        self.assertNotIn("*", upload)


if __name__ == "__main__":
    unittest.main()
