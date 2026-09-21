"""Verify a windowless distribution by running its isolated GUI smoke mode."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import time


def verify(executable, report, publish=None):
    binary = executable.read_bytes()
    pe = struct.unpack_from("<I", binary, 60)[0]
    if binary[pe:pe + 4] != b"PE\0\0" or struct.unpack_from("<H", binary, pe + 24 + 68)[0] != 2:
        raise RuntimeError("Expected a Windows GUI executable (PE subsystem 2).")
    report.parent.mkdir(parents=True, exist_ok=True)
    # Each run has a fresh report. A stale successful report cannot validate a failure.
    run_report = report.with_name(f"{report.stem}-{time.time_ns()}.json")
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    process = subprocess.Popen([str(executable), "--smoke-test", str(run_report)], startupinfo=startup)
    try:
        result = process.wait(timeout=45)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
        raise RuntimeError("Frozen GUI smoke test timed out.") from None
    if result != 0 or not run_report.is_file():
        raise RuntimeError(f"Frozen GUI failed without a valid report (exit {result}).")
    payload = json.loads(run_report.read_text(encoding="utf-8"))
    if not all(payload.get(key) for key in ("ok", "frozen", "cyrillic", "error_recovery", "confirmations", "settings_cache")):
        raise RuntimeError(f"Frozen GUI verification failed: {payload}")
    if not all(payload.get("embedded_runtime", {}).get(key) for key in ("python", "tcl", "tk", "theme")):
        raise RuntimeError("Frozen GUI could not verify its embedded runtime.")
    report.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    digest = hashlib.sha256(binary).hexdigest()
    if publish:
        # Publish only a verified build. A locked/running EXE leaves the previous
        # repository executable intact because replace is atomic on the same volume.
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=publish.parent, prefix=".KafkaAI-", suffix=".tmp", delete=False) as stream:
                temporary = Path(stream.name)
                stream.write(binary)
                stream.flush()
                os.fsync(stream.fileno())
            try:
                os.replace(temporary, publish)
            except PermissionError as error:
                raise RuntimeError(f"Build verified, but {publish.name} cannot be replaced. Close Kafka AI and retry; verified build: {executable}") from error
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        source_root = Path(__file__).resolve().parent
        inputs = {f"gui/{name}": hashlib.sha256((source_root / name).read_bytes()).hexdigest()
                  for name in ("app.py", "backend.py", "requirements.txt", "build.ps1", "verify_build.py")}
        publish.with_suffix(".build.json").write_text(json.dumps({
            "executable": publish.name, "sha256": digest, "inputs": inputs,
            "verification": payload,
        }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Frozen GUI, Unicode, embedded runtime and PE subsystem: OK")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=Path)
    parser.add_argument("report", type=Path)
    parser.add_argument("--publish", type=Path)
    arguments = parser.parse_args()
    verify(arguments.executable.resolve(), arguments.report.resolve(),
           arguments.publish.resolve() if arguments.publish else None)
