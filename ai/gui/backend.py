"""Script adapter. No toolkit operation is executed when this module is imported."""
from __future__ import annotations

import ctypes
from contextlib import contextmanager
import io
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import urlsplit

ACTIONS = {
    "install": "Установка окружения",
    "doctor": "Проверка готовности",
    "code": "Обновление code-index",
    "viking": "Обновление OpenViking",
}
DEFAULTS = {
    "workspace": "", "toolkit": "", "project": "", "codex": "", "node": "", "java": "",
    "indexer": "", "jar": "", "state": "", "ollama": "",
    "index_timeout": "1800", "mcp_timeout": "600", "theme": "System",
    "configuration_only": False, "skip_viking": False, "skip_daemon": False,
    "gpu": False, "rebuild": False, "human": True,
}
PARAMETERS = {
    "install": {
        "toolkit": "ToolkitRoot", "workspace": "WorkspaceRoot", "codex": "CodexHome",
        "indexer": "BslIndexerPath", "jar": "BslLanguageServerJar", "node": "NodePath",
        "java": "JavaPath", "state": "OpenVikingStateDir", "gpu": "OpenVikingGpu",
        "ollama": "OllamaUrl", "configuration_only": "ConfigurationOnly",
        "skip_viking": "SkipOpenVikingRuntime", "skip_daemon": "SkipDaemonStart",
        "index_timeout": "IndexReadyTimeoutSeconds", "mcp_timeout": "McpReadyTimeoutSeconds",
    },
    "code": {
        "toolkit": "ToolkitRoot", "workspace": "WorkspaceRoot", "codex": "CodexHome",
        "indexer": "BslIndexerPath", "node": "NodePath",
        "index_timeout": "IndexReadyTimeoutSeconds", "mcp_timeout": "McpReadyTimeoutSeconds",
    },
}
ACTION_FIELDS = {
    "install": tuple(PARAMETERS["install"]), "code": tuple(PARAMETERS["code"]),
    "doctor": ("workspace", "project", "codex", "node", "human"),
    "viking": ("workspace", "codex", "node", "state", "rebuild"),
}
ENTRYPOINTS = {"install": "install.cmd", "code": "update-code-index.cmd",
               "doctor": "doctor.mjs", "viking": "update-openviking.mjs"}
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def default_workspace():
    # Works both in source and in gui/dist/KafkaAI/KafkaAI.exe.
    origin = Path(sys.executable if getattr(sys, "frozen", False) else __file__)
    for parent in origin.parents:
        if parent.name.lower() == "ai" and parent.parent.name.lower() == "tools":
            return str(parent.parent.parent)
    return ""


def settings_path():
    return Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "KafkaAI/cache/settings.env"


def default_settings():
    return dict(DEFAULTS, workspace=default_workspace())


def parse_settings_env(text):
    """Read our allowlisted dotenv values; never expand variables or execute code."""
    keys = {"KAFKA_AI_" + key.upper(): key for key in DEFAULTS if key != "rebuild"}
    stored = {}
    for line in text.splitlines():
        name, separator, raw = line.strip().partition("=")
        if not separator or name.strip() not in keys:
            continue
        key = keys[name.strip()]
        raw = raw.strip()
        if type(DEFAULTS[key]) is bool:
            if raw.lower() in ("true", "1", "yes", "on"):
                stored[key] = True
            elif raw.lower() in ("false", "0", "no", "off"):
                stored[key] = False
        else:
            try:
                value = json.loads(raw) if raw.startswith('"') else raw[1:-1] if raw.startswith("'") and raw.endswith("'") else raw
            except ValueError:
                continue
            if isinstance(value, str) and not any(ord(char) < 32 for char in value):
                stored[key] = value
    return stored


def load_settings(path, legacy_path=None):
    values = default_settings()
    exists = path.is_file()
    if exists:
        stored = parse_settings_env(path.read_text(encoding="utf-8-sig"))
    else:
        stored = {}
        if legacy_path is None and path == settings_path():
            legacy_path = path.parent.parent / "settings.json"
        if legacy_path is not None:
            try:
                legacy = json.loads(legacy_path.read_text(encoding="utf-8-sig"))
                if isinstance(legacy, dict):
                    stored = legacy
            except (FileNotFoundError, ValueError):
                pass
    for key, default in DEFAULTS.items():
        if key in stored and type(stored[key]) is type(default):
            values[key] = stored[key]
    # Destructive choices are deliberately not restored.
    values["rebuild"] = False
    if values["theme"] not in ("System", "Light", "Dark"):
        values["theme"] = "System"
    try:
        validate_url(values["ollama"])
    except ValueError:
        values["ollama"] = ""
    if not exists:
        save_settings(path, values)
    return values


def save_settings(path, values):
    safe = {k: values[k] for k in DEFAULTS if k != "rebuild"}
    validate_url(safe["ollama"])
    for key, value in safe.items():
        if type(value) is not type(DEFAULTS[key]) or isinstance(value, str) and any(ord(char) < 32 for char in value):
            raise ValueError(f"Настройка {key}: недопустимое значение.")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="\n", dir=path.parent,
                                         delete=False, suffix=".tmp") as stream:
            temporary = Path(stream.name)
            stream.write("# Kafka AI GUI cache. UTF-8; no secrets; no variable expansion.\n")
            for key, value in safe.items():
                stream.write("KAFKA_AI_" + key.upper() + "=" + json.dumps(value, ensure_ascii=False) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def validate_url(value):
    if not value:
        return
    if any(ord(c) < 32 for c in value):
        raise ValueError("Ollama: URL содержит управляющие символы.")
    url = urlsplit(value)
    if (url.scheme not in ("http", "https") or not url.hostname or url.username
            or url.password or url.query or url.fragment or url.path not in ("", "/")):
        raise ValueError("Ollama: укажите http(s)://host:port без паролей, пути и параметров.")
    try:
        url.port
    except ValueError as error:
        raise ValueError("Ollama: некорректный порт.") from error


def validate(values, action):
    if action not in ACTIONS:
        raise ValueError("Неизвестная операция.")
    workspace = Path(values["workspace"])
    toolkit = Path(values["toolkit"]) if action in PARAMETERS and values["toolkit"] else workspace / "tools" / "ai"
    if not workspace.is_absolute() or not workspace.is_dir():
        raise ValueError("Выберите существующий абсолютный путь к корню Kafka workspace.")
    if (not toolkit.is_absolute() or toolkit.name.lower() != "ai" or toolkit.parent.name.lower() != "tools"
            or not (toolkit / ENTRYPOINTS[action]).is_file()):
        raise ValueError(f"Не найден штатный скрипт {ENTRYPOINTS[action]} в каталоге toolkit: {toolkit}")
    for key in set(ACTION_FIELDS[action]) & {"workspace", "toolkit", "project", "codex", "node", "java", "indexer", "jar", "state"}:
        value = values[key]
        if value and (not Path(value).is_absolute() or any(ord(c) < 32 for c in value)):
            raise ValueError(f"Поле {key}: требуется абсолютный путь без управляющих символов.")
    if action == "doctor" and values["project"] and not Path(values["project"]).is_dir():
        raise ValueError("Проверяемый проект: каталог не существует.")
    file_fields = {"node", "java", "indexer", "jar"} & set(ACTION_FIELDS[action])
    if action == "install" and values["configuration_only"]:
        file_fields = set()
    for key in file_fields:
        if values[key] and not Path(values[key]).is_file():
            raise ValueError(f"Поле {key}: выбранный файл не существует.")
    if action in ("install", "code"):
        for key in ("index_timeout", "mcp_timeout"):
            if not re.fullmatch(r"[0-9]+", values[key]) or not 60 <= int(values[key]) <= 3600:
                raise ValueError("Таймауты должны быть целыми числами от 60 до 3600 секунд.")
    if action == "install":
        validate_url(values["ollama"])
        if (not values["configuration_only"] and not values["skip_viking"] and values["gpu"]
                and values["ollama"] and values["ollama"].rstrip("/") != "http://ollama:11434"):
            raise ValueError("GPU относится к локальному Ollama. Для внешнего Ollama снимите флажок GPU.")
    return toolkit


def check_script_contract(source, action):
    """Fail before mutation if a newer script changes the supported parameter set."""
    marker = "# __KAFKA_AI_POWERSHELL__"
    if source.count(marker) != 1:
        raise ValueError("Изменился формат встроенного PowerShell. Обновите GUI вместе со скриптами.")
    body = source.split(marker, 1)[1].lstrip()
    header = body.split("\n)", 1)[0]
    declared = set(re.findall(r"(?m)^\s*(?:\[[^\]\r\n]+\])+\$(\w+)", header))
    expected = set(PARAMETERS[action].values())
    if declared != expected:
        raise ValueError("Параметры скрипта отличаются от поддерживаемых GUI. Обновите GUI: "
                         + ", ".join(sorted(declared ^ expected)))
    return body


def ps_quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def redact(text):
    text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
    text = re.sub(r"(?i)(bearer\s+)\S+", r"\1[скрыто]", text)
    text = re.sub(r'''(?ix)((?:[\w-]*(?:api[_-]?key|token|password|secret)|authorization)["']?\s*[=:]\s*)
                     (?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;]+)''', r"\1[скрыто]", text)
    return re.sub(r"(https?://)[^\s/@]+:[^\s/@]+@", r"\1[скрыто]@", text)


@contextmanager
def external_runtime():
    """Do not inject the bundled Python DLL directory into external tools."""
    frozen = getattr(sys, "frozen", False)
    if frozen:
        ctypes.windll.kernel32.SetDllDirectoryW(None)
    try:
        yield
    finally:
        if frozen:
            ctypes.windll.kernel32.SetDllDirectoryW(sys._MEIPASS)


class OperationLock:
    """Named Windows mutex: no stale lock files, shared by all GUI instances."""
    def __init__(self):
        self.handle = None

    def acquire(self):
        api = ctypes.WinDLL("kernel32", use_last_error=True)
        api.CreateMutexW.argtypes = [ctypes.c_void_p, ctypes.c_bool, ctypes.c_wchar_p]
        api.CreateMutexW.restype = ctypes.c_void_p
        self.handle = api.CreateMutexW(None, True, "Local\\KafkaAI.Toolkit.Operation.v1")
        if not self.handle:
            raise ctypes.WinError(ctypes.get_last_error())
        if ctypes.get_last_error() == 183:
            self.release()
            raise RuntimeError("Другая копия GUI уже выполняет операцию. Дождитесь её завершения.")

    def release(self):
        if self.handle:
            api = ctypes.WinDLL("kernel32", use_last_error=True)
            api.CloseHandle.argtypes = [ctypes.c_void_p]
            api.CloseHandle(self.handle)
            self.handle = None


def powershell():
    return str(Path(os.environ.get("SystemRoot", r"C:\Windows")) /
               "System32/WindowsPowerShell/v1.0/powershell.exe")


def probe(command, description, minimum=None):
    try:
        # Commands here are fixed, read-only dependency probes; output is not logged.
        with external_runtime():
            result = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, timeout=30,
                                    creationflags=NO_WINDOW)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(f"{description}: команда недоступна или не ответила за 30 с.") from error
    if result.returncode:
        raise RuntimeError(f"{description}: проверка не пройдена. Проверьте установку и PATH.")
    if minimum:
        match = re.search(rb'(?:version\s+")?v?(\d+)\.', result.stdout + result.stderr)
        if not match or int(match[1]) < minimum:
            raise RuntimeError(f"{description}: требуется версия {minimum} или новее.")
    return result.stdout


def resolve_node(values, action):
    if values["node"]:
        return values["node"]
    if action in PARAMETERS:
        if os.environ.get("CODE_INDEX_NODE"):
            return os.environ["CODE_INDEX_NODE"]
        installed = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "nodejs/node.exe"
        if installed.is_file():
            return str(installed)
    return shutil.which("node")


def prerequisites(values, action, emit):
    emit("stage", "Проверка внешних зависимостей")
    toolkit = validate(values, action)
    if not Path(powershell()).is_file():
        raise RuntimeError("Не найден Windows PowerShell 5.1 (в том числе для блокировки операций).")
    if not (toolkit / "mcp/toolkit-operation-lock.ps1").is_file():
        raise RuntimeError("В toolkit отсутствует общая блокировка операций. Обновите scripts и GUI вместе.")
    if action == "install" and values["configuration_only"]:
        emit("log", "Только конфигурация: runtime, Java, Docker и готовность MCP не проверяются.")
        return None
    node = resolve_node(values, action)
    if not node:
        raise RuntimeError("Node.js не найден. Установите Node.js LTS с https://nodejs.org/ (требуется 18+), перезапустите терминал и GUI, затем проверьте: node --version. Либо укажите полный путь к node.exe в форме.")
    try:
        probe([node, "--version"], "Node.js", 18)
    except RuntimeError as error:
        raise RuntimeError("Node.js не запускается или его версия ниже 18. Установите Node.js LTS с https://nodejs.org/, "
                           "перезапустите GUI и проверьте: node --version. Либо исправьте путь к node.exe.") from error
    dependencies = ["git"] if action in ("doctor", "viking", "install") else []
    if action == "doctor" or (action == "viking" and not (values["state"] or os.environ.get("KAFKA_OPENVIKING_STATE_DIR"))):
        try:
            probe([powershell(), "-NoLogo", "-NoProfile", "-NonInteractive", "-Command",
                   "if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { exit 127 }; exit 0"], "Codex CLI")
        except RuntimeError as error:
            raise RuntimeError("Codex CLI недоступен. Установите: npm install -g @openai/codex. "
                               "Перезапустите терминал и GUI, проверьте: codex --version. "
                               "Если CLI уже установлен, проверьте PATH. Операция не запущена.") from error
    for name in dependencies:
        if not shutil.which(name):
            raise RuntimeError(f"Не найден {name} в PATH. Установите его и перезапустите GUI.")
    if "git" in dependencies:
        probe([shutil.which("git"), "--version"], "Git")
    if action == "install" and not values["configuration_only"]:
        java = values["java"] or os.environ.get("BSL_LANGUAGE_SERVER_JAVA")
        if java:
            probe([java, "-version"], "Java", 25)
        else:
            emit("log", "Java 25+: путь из конфигурации BSL LS проверит штатный установщик.")
        if not values["skip_viking"]:
            docker = shutil.which("docker")
            if not docker:
                raise RuntimeError("Не найден Docker Desktop. Установите его и включите Linux containers.")
            mode = probe([docker, "info", "--format", "{{.OSType}}"], "Docker Desktop").strip().lower()
            if mode != b"linux":
                raise RuntimeError("Переключите Docker Desktop в режим Linux containers.")
            probe([docker, "compose", "version"], "Docker Compose")
    emit("log", "Внешние команды доступны. Точные пути и готовность проверит выбранный скрипт.")
    return node


def prepare(values, action, directory, node):
    toolkit = validate(values, action)
    env = os.environ.copy()
    env["KAFKA_AI_NO_PAUSE"] = "1"
    # Child JS tools may spawn node by name.
    if node:
        env["PATH"] = str(Path(node).parent) + os.pathsep + env.get("PATH", "")
    if values["codex"]:
        env["CODEX_HOME"] = values["codex"]
    if action in ("install", "viking") and values["state"]:
        env["KAFKA_OPENVIKING_STATE_DIR"] = values["state"]
    if action == "doctor":
        return [node, str(toolkit / "doctor.mjs"), *(["--human"] if values["human"] else []), "--project-root",
                values["project"] or values["workspace"]], env, None
    if action == "viking":
        return [node, str(toolkit / "update-openviking.mjs")] + (
            ["--rebuild"] if values["rebuild"] else []), env, None
    name = "install.cmd" if action == "install" else "update-code-index.cmd"
    source = (toolkit / name).read_text(encoding="utf-8-sig")
    script = directory / "operation.ps1"
    script.write_text(check_script_contract(source, action), encoding="utf-8-sig")
    parameters = {"ToolkitRoot": str(toolkit), "WorkspaceRoot": values["workspace"],
                  "IndexReadyTimeoutSeconds": int(values["index_timeout"]),
                  "McpReadyTimeoutSeconds": int(values["mcp_timeout"])}
    for key, parameter in PARAMETERS[action].items():
        if key not in ("workspace", "toolkit", "index_timeout", "mcp_timeout") and values[key]:
            parameters[parameter] = values[key]
    if node:
        parameters["NodePath"] = node
    # Splat typed values rather than embedding user input in command text.
    literals = []
    for key, value in parameters.items():
        literal = "$true" if value is True else str(value) if type(value) is int else ps_quote(value)
        literals.append(f"{key} = {literal}")
    stages = directory / "stages.txt" if action == "install" else None
    wrapper = directory / "launch.ps1"
    wrapper.write_text(
        "$ErrorActionPreference = 'Stop'\n"
        "[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)\n"
        "[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)\n"
        "$OutputEncoding = [Console]::OutputEncoding\n"
        "$global:LASTEXITCODE = 0\n"
        "$parameters = @{\n" + "\n".join(literals) + "\n}\n"
        "try { & " + ps_quote(script) + " @parameters; if ($?) { $result = 0 } else { $result = 1 } }\n"
        "catch { Write-Host $_.Exception.Message; $result = 1; "
        + ("[IO.File]::AppendAllText(" + ps_quote(stages) + ", '[ERROR] ' + $_.Exception.Message + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))" if stages else "") + " }\n"
        + ("if ($result -ne 0) {\n"
           "[IO.File]::AppendAllText(" + ps_quote(stages) + ", '[ERROR] Ошибка установки. Подробности выше; нажмите Enter в консоли для завершения.' + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))\n"
           "Read-Host 'Installation failed. Press Enter to return to GUI'\n}\n"
           if action == "install" else "") + "exit $result\n", encoding="utf-8-sig")
    env["PSModulePath"] = ""
    if stages:
        env["KAFKA_AI_GUI_STAGES"] = str(stages)
    return [powershell(), "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(wrapper)], env, stages


class Runner:
    def __init__(self, fixture=False):
        self.events = queue.Queue(maxsize=2048)
        self.busy = False
        self.fixture = fixture
        self.fixture_exit_code = 0
        self._start_lock = threading.Lock()

    def emit(self, kind, value):
        self.events.put((kind, value))

    def emit_stage(self, value):
        text = redact(value)
        self.emit("error" if text.startswith("[ERROR]") else "stage", text)

    def start(self, values, action):
        with self._start_lock:
            if self.busy:
                return False
            self.busy = True
            try:
                threading.Thread(target=self._run, args=(dict(values), action), daemon=False).start()
            except Exception:
                self.busy = False
                raise
            return True

    def _run(self, values, action):
        lock = OperationLock()
        result = 1
        process = None
        try:
            lock.acquire()
            with tempfile.TemporaryDirectory(prefix="kafka-ai-gui-") as folder:
                if self.fixture:
                    command = [sys.executable]
                    if not getattr(sys, "frozen", False):
                        command.append(str(Path(__file__).with_name("app.py")))
                    command.extend(["--fixture-worker", action])
                    command.extend(["--fixture-exit-code", str(self.fixture_exit_code)])
                    env, stages = os.environ.copy(), None
                else:
                    node = prerequisites(values, action, self.emit)
                    command, env, stages = prepare(values, action, Path(folder), node)
                # The same UTF-8 pipe contract applies to real and demo Python children.
                env["PYTHONIOENCODING"] = "utf-8"
                interactive = action == "install" and not self.fixture
                self.emit("stage", "Работа в окне установщика" if interactive else ACTIONS[action])
                if interactive:
                    self.emit("log", "Ответьте на вопросы в открывшейся консоли. При ошибке прочитайте её и нажмите Enter.")
                # Restore Windows DLL lookup before running external executables from a frozen app.
                with external_runtime():
                    process = subprocess.Popen(command, cwd=values["workspace"], env=env,
                        stdin=None if interactive else subprocess.DEVNULL,
                        stdout=None if interactive else subprocess.PIPE,
                        stderr=None if interactive else subprocess.STDOUT,
                        creationflags=subprocess.CREATE_NEW_CONSOLE if interactive else NO_WINDOW)
                if interactive:
                    stages.touch()
                    pending = b""
                    with stages.open("rb") as stream:
                        while True:
                            pending += stream.read(8192)
                            while b"\n" in pending:
                                line, pending = pending.split(b"\n", 1)
                                self.emit_stage(line.decode("utf-8-sig", errors="replace").strip())
                            if process.poll() is not None:
                                tail = pending + stream.read()
                                if tail:
                                    self.emit_stage(tail.decode("utf-8-sig", errors="replace").strip())
                                break
                            time.sleep(.2)
                else:
                    # TextIOWrapper preserves multibyte characters split across pipe reads.
                    # The limit is in decoded characters and keeps queue entries bounded.
                    with io.TextIOWrapper(process.stdout, encoding="utf-8", errors="replace") as output:
                        while line := output.readline(8192):
                            text = redact(line.rstrip())
                            self.emit("stage" if text.startswith(("==>", "openviking-sync:")) else "log", text)
                result = process.wait()
                if result:
                    self.emit("error", f"{ACTIONS[action]}: код {result}. Готовность не подтверждена. "
                              "Проверьте журнал; для установки — сообщение в консоли. Автоматического повтора нет.")
        except Exception as error:
            self.emit("error", redact(str(error)))
        finally:
            # A logging failure must not unlock the UI while an updater is still running.
            if process is not None and process.poll() is None:
                self.emit("stage", "Ожидание завершения скрипта после ошибки журнала…")
                process.wait()
            lock.release()
            self.emit("done", result)
            # UI resets busy only after consuming done, so it cannot mix event streams.


SETTINGS_FORMAT = "kafka-ai/settings-v1"


def checked_transfer(values):
    expected = set(DEFAULTS) - {"rebuild"}
    if not isinstance(values, dict) or set(values) != expected:
        raise ValueError("Набор полей настроек не соответствует этой версии приложения.")
    for key, value in values.items():
        if type(value) is not type(DEFAULTS[key]) or isinstance(value, str) and any(ord(c) < 32 for c in value):
            raise ValueError("Некорректный тип или значение настройки: " + key)
    if values["theme"] not in ("System", "Light", "Dark"):
        raise ValueError("Неизвестная тема оформления.")
    for key in ("index_timeout", "mcp_timeout"):
        if not re.fullmatch(r"[0-9]+", values[key]) or not 60 <= int(values[key]) <= 3600:
            raise ValueError("Таймауты: целые числа от 60 до 3600 секунд.")
    validate_url(values["ollama"])
    result = dict(values)
    if "rebuild" in DEFAULTS:
        result["rebuild"] = False
    return result


def export_settings(path, values):
    safe = checked_transfer({k: values[k] for k in DEFAULTS if k != "rebuild"})
    safe.pop("rebuild", None)
    payload = json.dumps({"format": SETTINGS_FORMAT, "settings": safe}, ensure_ascii=False, indent=2) + "\n"
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False, suffix=".tmp") as stream:
            temporary = Path(stream.name)
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def import_settings(path, cache):
    if path.stat().st_size > 1024 * 1024:
        raise ValueError("Файл настроек слишком большой.")
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Повторяющееся поле: " + key)
            result[key] = value
        return result
    payload = json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=unique_object)
    if not isinstance(payload, dict) or set(payload) != {"format", "settings"} or payload["format"] != SETTINGS_FORMAT:
        raise ValueError("Формат настроек принадлежит другому приложению или версии.")
    values = checked_transfer(payload["settings"])
    # Atomic replacement: validation/write failures preserve the previous cache.
    save_settings(cache, values)
    return values
