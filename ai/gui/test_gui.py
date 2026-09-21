"""Offline adapter tests. Production installer/updater bodies are never executed."""
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

import backend as b

TOOLKIT = Path(__file__).resolve().parents[1]


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kafka-gui-check-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "Рабочее место ' & $safe"
        self.toolkit = self.root / "tools/ai"
        self.toolkit.mkdir(parents=True)
        for name in b.ENTRYPOINTS.values():
            shutil.copyfile(TOOLKIT / name, self.toolkit / name)
        (self.toolkit / "mcp").mkdir()
        (self.toolkit / "mcp/toolkit-operation-lock.ps1").touch()
        self.values = dict(b.DEFAULTS, workspace=str(self.root))
        self.output = self.root / "adapter"
        self.output.mkdir()

    def test_all_declared_powershell_parameters(self):
        for action in b.PARAMETERS:
            source = (self.toolkit / b.ENTRYPOINTS[action]).read_text(encoding="utf-8-sig")
            body = b.check_script_contract(source, action)
            # This fixture has the real param declaration, but none of the real body.
            param_block = body.split("\n)", 1)[0] + "\n)\n"
            self.values.update(toolkit=str(self.toolkit), codex=str(self.root / "Profile"),
                               state=str(self.root / "Данные"), ollama="http://localhost:11434",
                               gpu=True, configuration_only=True, skip_viking=True, skip_viking_initial_sync=True,
                               skip_daemon=True, index_timeout="120", mcp_timeout="180")
            for key in ("node", "java", "indexer", "jar"):
                file = self.root / (key + (".jar" if key == "jar" else ".exe"))
                file.touch()
                self.values[key] = str(file)
            command, env, _ = b.prepare(self.values, action, self.output, self.values["node"])
            fixture = param_block + "[ordered]@{ bound = $PSBoundParameters; profile = $env:CODEX_HOME } | ConvertTo-Json -Depth 4\n"
            (self.output / "operation.ps1").write_text(fixture, encoding="utf-8-sig")
            result = subprocess.run(command, env=env, capture_output=True, timeout=15,
                                    creationflags=b.NO_WINDOW)
            self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8", errors="replace"))
            payload = json.loads(result.stdout.decode("utf-8-sig"))
            bound = payload["bound"]
            self.assertEqual(set(bound), set(b.PARAMETERS[action].values()))
            for key, parameter in b.PARAMETERS[action].items():
                expected = int(self.values[key]) if key.endswith("_timeout") else self.values[key]
                if isinstance(expected, bool):
                    self.assertTrue(bound[parameter]["IsPresent"])
                else:
                    self.assertEqual(bound[parameter], expected)
            self.assertEqual(payload["profile"], self.values["codex"])

    def test_unknown_script_parameter_blocks_run(self):
        source = (TOOLKIT / "install.cmd").read_text(encoding="utf-8-sig")
        source = source.replace("[string]$WorkspaceRoot,", "[string]$Unexpected,\n    [string]$WorkspaceRoot,")
        with self.assertRaisesRegex(ValueError, "Unexpected"):
            b.check_script_contract(source, "install")

    def test_powershell_failure_exit_code(self):
        command, env, _ = b.prepare(self.values, "code", self.output, "node.exe")
        (self.output / "operation.ps1").write_text("exit 7\n", encoding="utf-8-sig")
        result = subprocess.run(command, env=env, capture_output=True, timeout=15, creationflags=b.NO_WINDOW)
        self.assertNotEqual(result.returncode, 0)

    def test_installer_interactive_input_and_error_stage(self):
        command, env, stages = b.prepare(self.values, "install", self.output, "node.exe")
        fixture = "$answer = Read-Host 'Fixture question'; if ($answer -ne 'continue') { exit 9 }; Write-Output 'Ответ принят'\n"
        (self.output / "operation.ps1").write_text(fixture, encoding="utf-8-sig")
        result = subprocess.run(command, env=env, input=b"continue\n", capture_output=True,
                                timeout=15, creationflags=b.NO_WINDOW)
        self.assertEqual(result.returncode, 0)
        self.assertIn("Ответ принят", result.stdout.decode("utf-8-sig"))
        (self.output / "operation.ps1").write_text("exit 7\n", encoding="utf-8-sig")
        result = subprocess.run(command, env=env, input=b"\n", capture_output=True,
                                timeout=15, creationflags=b.NO_WINDOW)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Ошибка установки", stages.read_text(encoding="utf-8"))

    def test_powershell_error_details_reach_gui(self):
        command, env, stages = b.prepare(self.values, "install", self.output, "node.exe")
        source = (TOOLKIT / "install.cmd").read_text(encoding="utf-8-sig")
        trap = source[source.index("trap {"):source.index("\n}\n", source.index("trap {")) + 3]
        for fixture in ("throw 'Ошибка fixture: отсутствует Codex CLI'",
                        "function Assert-CRMPath { param($Path, $WorkspaceRoot) }\n" + trap + "throw 'Ошибка fixture: отсутствует Codex CLI'"):
            stages.unlink(missing_ok=True)
            (self.output / "operation.ps1").write_text(fixture, encoding="utf-8-sig")
            result = subprocess.run(command, env=env, input=b"\n", capture_output=True, timeout=15, creationflags=b.NO_WINDOW)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Ошибка fixture: отсутствует Codex CLI", stages.read_text(encoding="utf-8"))
        runner = b.Runner()
        runner.emit_stage("[ERROR] Codex CLI missing token=SECRET")
        kind, message = runner.events.get_nowait()
        self.assertEqual(kind, "error")
        self.assertIn("Codex CLI missing", message)
        self.assertNotIn("SECRET", message)

    def test_doctor_formats_and_rebuild(self):
        self.values["human"] = False
        command, _, _ = b.prepare(self.values, "doctor", self.output, "node.exe")
        self.assertNotIn("--human", command)
        self.assertEqual(command[-2:], ["--project-root", str(self.root)])
        self.values["human"] = True
        self.assertIn("--human", b.prepare(self.values, "doctor", self.output, "node.exe")[0])
        self.assertNotIn("--rebuild", b.prepare(self.values, "viking", self.output, "node.exe")[0])
        self.values["rebuild"] = True
        self.assertEqual(b.prepare(self.values, "viking", self.output, "node.exe")[0][-1], "--rebuild")

    def test_hidden_invalid_parameters_do_not_block_other_actions(self):
        self.values.update(java="relative", index_timeout="wrong", ollama="not a url")
        b.validate(self.values, "doctor")
        b.validate(self.values, "viking")
        with self.assertRaises(ValueError):
            b.validate(self.values, "install")

    def test_range_and_gpu_validation(self):
        for value in ("0", "59", "3601", "NaN", "1.5"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                b.validate(dict(self.values, index_timeout=value), "code")
        with self.assertRaisesRegex(ValueError, "GPU"):
            b.validate(dict(self.values, gpu=True, ollama="http://external:11434"), "install")

    def test_settings_allowlist_and_destructive_flag(self):
        file = self.root / "settings.env"
        b.save_settings(file, dict(self.values, token="NEVER_PERSIST", rebuild=True, theme="Dark"))
        text = file.read_text(encoding="utf-8")
        self.assertNotIn("NEVER_PERSIST", text)
        self.assertNotIn("KAFKA_AI_REBUILD", text)
        loaded = b.load_settings(file)
        self.assertFalse(loaded["rebuild"])
        self.assertEqual(loaded["theme"], "Dark")
        file.write_text('KAFKA_AI_GPU=invalid\nKAFKA_AI_THEME="bad"\nKAFKA_AI_REBUILD=true\n', encoding="utf-8")
        self.assertFalse(b.load_settings(file)["gpu"])
        self.assertFalse(b.load_settings(file)["rebuild"])
        self.assertEqual(b.load_settings(file)["theme"], "System")
        file.write_text("broken", encoding="utf-8")
        self.assertEqual(b.load_settings(file)["human"], True)

    def test_secret_urls_never_saved(self):
        for url in ("http://user:password@host", "https://host?token=test", "http://host/secret", "http://host:bad"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                b.save_settings(self.root / "settings.env", dict(self.values, ollama=url))
        self.assertFalse((self.root / "settings.env").exists())

    def test_missing_env_is_created_with_defaults(self):
        file = self.root / "cache/settings.env"
        values = b.load_settings(file)
        self.assertTrue(file.is_file())
        self.assertEqual(values, b.default_settings())
        self.assertEqual(b.load_settings(file), values)
        self.assertIn('KAFKA_AI_INDEX_TIMEOUT="1800"', file.read_text(encoding="utf-8"))

    def test_env_roundtrip_special_characters_and_no_expansion(self):
        file = self.root / "settings.env"
        values = dict(self.values, workspace=r'C:\Каталог #1\"${HOME}"', gpu=True, human=False, theme="Light")
        b.save_settings(file, values)
        self.assertEqual(b.load_settings(file), values)
        file.write_text("KAFKA_AI_NODE='C:\\Program Files\\node.exe'\nKAFKA_AI_GPU=yes\n", encoding="utf-8")
        self.assertEqual(b.load_settings(file)["node"], r"C:\Program Files\node.exe")
        self.assertTrue(b.load_settings(file)["gpu"])

    def test_json_migration_only_when_env_missing(self):
        file = self.root / "cache/settings.env"
        legacy = self.root / "settings.json"
        legacy.write_text(json.dumps(dict(self.values, theme="Dark", token="NEVER_COPY", rebuild=True)), encoding="utf-8")
        migrated = b.load_settings(file, legacy_path=legacy)
        self.assertEqual(migrated["workspace"], self.values["workspace"])
        self.assertEqual(migrated["theme"], "Dark")
        self.assertFalse(migrated["rebuild"])
        self.assertNotIn("NEVER_COPY", file.read_text(encoding="utf-8"))
        legacy.write_text('{"theme":"Light"}', encoding="utf-8")
        self.assertEqual(b.load_settings(file, legacy_path=legacy)["theme"], "Dark")

    def test_failed_save_preserves_previous_env(self):
        file = self.root / "settings.env"
        b.save_settings(file, self.values)
        previous = file.read_bytes()
        with patch.object(b.os, "replace", side_effect=OSError("fixture lock")), self.assertRaises(OSError):
            b.save_settings(file, dict(self.values, theme="Dark"))
        self.assertEqual(file.read_bytes(), previous)
        self.assertFalse(list(file.parent.glob("*.tmp")))

    def test_masking(self):
        for text in ('{"api_key": "SECRET with spaces"}', "token=SECRET", "Authorization: Bearer SECRET", "https://user:SECRET@host"):
            self.assertNotIn("SECRET", b.redact(text))

    def test_configuration_only_does_not_probe_runtime(self):
        with patch.object(b, "probe") as probe:
            result = b.prerequisites(dict(self.values, configuration_only=True), "install", lambda *_: None)
        self.assertIsNone(result)
        probe.assert_not_called()

    def test_java_on_path_does_not_override_bsl_configuration(self):
        with patch.object(b, "probe", return_value=b"v18.0.0") as probe, \
             patch.object(b, "resolve_node", return_value="node.exe"), \
             patch.object(b.shutil, "which", return_value="irrelevant-java-or-git.exe"), \
             patch.dict(os.environ, {"BSL_LANGUAGE_SERVER_JAVA": ""}):
            b.prerequisites(dict(self.values, skip_viking=True), "install", lambda *_: None)
        self.assertFalse(any(call.args[1] == "Java" for call in probe.call_args_list))

    def test_wrong_docker_mode_blocks_install(self):
        def probe(command, *_):
            return b"windows" if "info" in command else b"v18.0.0"
        with patch.object(b, "probe", side_effect=probe), \
             patch.object(b, "resolve_node", return_value="node.exe"), \
             patch.object(b.shutil, "which", return_value="fixture.exe"), \
             patch.dict(os.environ, {"BSL_LANGUAGE_SERVER_JAVA": ""}), self.assertRaisesRegex(RuntimeError, "Linux"):
            b.prerequisites(self.values, "install", lambda *_: None)

    def test_explicit_openviking_state_does_not_require_codex(self):
        with patch.object(b, "probe", return_value=b"v18.0.0"), \
             patch.object(b, "resolve_node", return_value="node.exe"), \
             patch.object(b.shutil, "which", side_effect=lambda name: "git.exe" if name == "git" else None):
            b.prerequisites(dict(self.values, state=str(self.root / "state")), "viking", lambda *_: None)

    def test_missing_or_old_node_has_actionable_error(self):
        with patch.object(b, "resolve_node", return_value=None), self.assertRaisesRegex(RuntimeError, "https://nodejs.org/"):
            b.prerequisites(self.values, "doctor", lambda *_: None)
        with patch.object(b, "resolve_node", return_value="node.exe"), patch.object(b, "probe", side_effect=RuntimeError("old version")), self.assertRaisesRegex(RuntimeError, "node --version"):
            b.prerequisites(self.values, "doctor", lambda *_: None)

    def test_missing_codex_doctor_has_install_command(self):
        def check(command, description, minimum=None):
            if description == "Codex CLI":
                raise RuntimeError("missing")
            return b"v24.0.0"
        with patch.object(b, "resolve_node", return_value="node.exe"), patch.object(b, "probe", side_effect=check), self.assertRaisesRegex(RuntimeError, "npm install -g @openai/codex"):
            b.prerequisites(self.values, "doctor", lambda *_: None)

    def test_action_form_coverage(self):
        from app import FORM_KEYS, SWITCHES
        for action, keys in b.ACTION_FIELDS.items():
            represented = set(FORM_KEYS[action]) | {item[0] for item in SWITCHES.get(action, ())}
            self.assertEqual(represented, set(keys), action)

    def test_streaming_unicode_failure_and_retry(self):
        node = shutil.which("node")
        self.assertIsNotNone(node)
        # Writes one Cyrillic codepoint across byte 8192 and then fails deliberately.
        text = "x" * 8191 + "Ёжик в тумане"
        command = [node, "-e", "process.stdout.write(" + json.dumps(text) + ");process.exitCode=7"]
        runner = b.Runner()
        with patch.object(b, "prerequisites", return_value=node), \
             patch.object(b, "prepare", return_value=(command, os.environ.copy(), None)):
            self.assertTrue(runner.start(self.values, "doctor"))
            self.assertFalse(runner.start(self.values, "doctor"))
            events = []
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                event = runner.events.get(timeout=15)
                events.append(event)
                if event[0] == "done":
                    break
            self.assertEqual(events[-1], ("done", 7))
            self.assertEqual("".join(value for kind, value in events if kind == "log"), text)
            self.assertTrue(any(kind == "error" for kind, _ in events))
            runner.busy = False
            command[-1] = "process.stdout.write('Повторный запуск');"
            self.assertTrue(runner.start(self.values, "doctor"))
            while (event := runner.events.get(timeout=15))[0] != "done":
                pass
            self.assertEqual(event, ("done", 0))



class SettingsTransferTests(unittest.TestCase):
    setUp = AdapterTests.setUp
    def test_transfer_replaces_cache_and_roundtrips(self):
        cache = self.root / "cache.env"
        exported = self.root / "settings.json"
        b.save_settings(cache, dict(self.values, theme="Dark"))
        source = dict(self.values, theme="Light", index_timeout="240")
        b.export_settings(exported, source)
        imported = b.import_settings(exported, cache)
        self.assertEqual(imported, b.load_settings(cache))
        self.assertEqual(imported["theme"], "Light")
        self.assertEqual(imported["index_timeout"], "240")
        self.assertEqual(set(json.loads(exported.read_text(encoding="utf-8"))["settings"]), set(b.DEFAULTS)-{"rebuild"})

    def test_bad_import_preserves_cache(self):
        cache = self.root / "cache.env"
        exported = self.root / "settings.json"
        b.save_settings(cache, self.values)
        previous = cache.read_bytes()
        b.export_settings(exported, self.values)
        payload = json.loads(exported.read_text(encoding="utf-8"))
        cases = [{}, dict(payload, format="other/settings-v1"),
                 dict(payload, settings=dict(payload["settings"], unknown="x")),
                 dict(payload, settings=dict(payload["settings"], human="false")),
                 dict(payload, settings=dict(payload["settings"], theme="invalid")),
                 dict(payload, settings=dict(payload["settings"], index_timeout="1")),
                 dict(payload, settings={})]
        for item in cases:
            exported.write_text(json.dumps(item), encoding="utf-8")
            with self.assertRaises(ValueError):
                b.import_settings(exported, cache)
            self.assertEqual(cache.read_bytes(), previous)
        exported.write_text('{"format":"x","format":"y"}', encoding="utf-8")
        with self.assertRaises(ValueError):
            b.import_settings(exported, cache)
        self.assertEqual(cache.read_bytes(), previous)

    def test_failed_import_write_preserves_cache(self):
        cache, exported = self.root / "cache.env", self.root / "settings.json"
        b.save_settings(cache, self.values)
        b.export_settings(exported, dict(self.values, theme="Light"))
        previous = cache.read_bytes()
        with patch.object(b.os, "replace", side_effect=OSError("locked")), self.assertRaises(OSError):
            b.import_settings(exported, cache)
        self.assertEqual(cache.read_bytes(), previous)


if __name__ == "__main__":
    unittest.main()
