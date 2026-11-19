import argparse
from codecs import BOM_UTF8
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import random
import re
from stat import S_ISREG
import sys
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen


BATCH_RECORDS = 1000
BATCH_BYTES = 5 * 1024 * 1024
MAX_REQUEST_BYTES = 100 * 1024 * 1024
MAX_RETRIES = 3


def find_log_files(root):
    def raise_scan_error(error):
        raise error

    for directory, _, filenames in os.walk(root, onerror=raise_scan_error):
        for name in filenames:
            if name.lower().endswith(".log"):
                file = Path(directory, name)
                if S_ISREG(file.stat().st_mode):
                    yield file


def index_name(file, prefix):
    process = re.match(r"(.+?)_[0-9]+", file.parent.name)
    if process is None:
        raise ValueError(f"{file.parent}: expected a process directory such as rphost_1234")
    if not re.fullmatch(r"[0-9]{8}", file.stem):
        raise ValueError(f"{file}: expected a YYMMDDHH.log filename")
    try:
        day = datetime.strptime(f"20{file.stem}", "%Y%m%d%H").strftime("%Y%m%d")
    except ValueError:
        raise ValueError(f"{file}: invalid date or hour in the filename") from None

    name = f"{process[1]}{prefix}{day}"
    if (name != name.lower() or name[0] in "-_+" or len(name.encode("utf-8")) > 255
            or re.search(r'[\x00-\x20\\/*?"<>|,#:]', name)):
        raise ValueError(f"Invalid Elasticsearch index name {name!r}")
    return name


def reject_json_constant(value):
    raise ValueError(f"Invalid JSON constant {value}")


def validate_document(body, file, line_number):
    try:
        document = json.loads(
            body.decode("utf-8"),
            parse_int=str,
            parse_float=str,
            parse_constant=reject_json_constant,
        )
        if not isinstance(document, dict):
            raise ValueError("Expected a JSON object")
    except (ValueError, RecursionError):
        raise ValueError(f"{file}:{line_number}: expected a valid UTF-8 JSON object") from None


def post_batch(url, batch, file):
    payload = b"".join(record for _, record in batch)
    request = Request(url, data=payload, headers={"Content-Type": "application/x-ndjson"})
    location = f"{file}:{batch[0][0]}"
    try:
        with urlopen(request, timeout=120) as response:
            result = json.load(response)
    except HTTPError as error:
        error.close()
        if error.code == 429:
            return batch
        raise RuntimeError(f"{location}: Elasticsearch returned HTTP {error.code}") from None
    except (OSError, ValueError) as error:
        raise RuntimeError(f"{location}: _bulk request failed ({error})") from None

    items = result.get("items") if isinstance(result, dict) else None
    if not isinstance(items, list) or len(items) != len(batch):
        raise RuntimeError(f"{location}: unexpected _bulk response")

    rejected = []
    for record, item in zip(batch, items):
        line_number, _ = record
        action = item.get("create") if isinstance(item, dict) else None
        if not isinstance(action, dict):
            raise RuntimeError(f"{file}:{line_number}: unexpected _bulk item")

        status = action.get("status")
        if status == 201:
            continue
        if status == 429:
            rejected.append(record)
            continue
        error = action.get("error")
        error_type = error.get("type") if isinstance(error, dict) else None
        if status == 409 and error_type == "version_conflict_engine_exception":
            continue

        raise RuntimeError(f"{file}:{line_number}: indexing failed (HTTP {status}, {error_type})")
    return rejected


def send_batch(url, batch, file):
    pending = batch
    for attempt in range(MAX_RETRIES + 1):
        if attempt:
            time.sleep(random.uniform(0.5, 1.0) * 2 ** (attempt - 1))
        pending = post_batch(url, pending, file)
        if not pending:
            return
    raise RuntimeError(
        f"{file}:{pending[0][0]}: HTTP 429 after {MAX_RETRIES + 1} attempts "
        f"({len(pending)} rejected records)"
    )


def import_file(file, index, url, limit):
    file_id = hashlib.sha256(str(file).encode("utf-8"))
    batch = []
    batch_size = 0
    count = 0

    with file.open("rb") as source:
        lines = iter(lambda: source.readline(MAX_REQUEST_BYTES + 1), b"")
        for line_number, line in enumerate(lines, start=1):
            if len(line) > MAX_REQUEST_BYTES:
                raise ValueError(f"{file}:{line_number}: log line exceeds {MAX_REQUEST_BYTES} bytes")
            if line.startswith(BOM_UTF8):
                line = line[len(BOM_UTF8):]
            body = line.strip(b" \t\r\n")
            if not body:
                continue

            # The validated JSON object is the document body, preserving numeric tokens exactly.
            validate_document(body, file, line_number)
            document_id = file_id.copy()
            document_id.update(f"\0{line_number}\0".encode("ascii"))
            document_id.update(body)
            action = {"create": {"_index": index, "_id": document_id.hexdigest()}}
            header = json.dumps(action, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            record_size = len(header) + len(body) + 2
            if record_size > MAX_REQUEST_BYTES:
                raise ValueError(f"{file}:{line_number}: bulk record exceeds {MAX_REQUEST_BYTES} bytes")

            if url is not None:
                if batch and (len(batch) >= BATCH_RECORDS or batch_size + record_size > BATCH_BYTES):
                    send_batch(url, batch, file)
                    batch.clear()
                    batch_size = 0
                batch.append((line_number, b"\n".join((header, body, b""))))
                batch_size += record_size

            count += 1
            if count == limit:
                break

    if batch:
        send_batch(url, batch, file)
    return count


def main():
    command = f'python "{Path(__file__).resolve()}"'
    parser = argparse.ArgumentParser(
        add_help=False,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description=(
            "Импортирует JSON-записи технологического журнала 1С в Elasticsearch.\n"
            "Имя индекса состоит из части имени каталога перед _<PID>, префикса\n"
            "и даты YYYYMMDD из имени файла. С префиксом -kfk- для файла\n"
            "rphost_11972\\26111709.log получится rphost-kfk-20261117."
        ),
        epilog=(
            "Проверка первых пяти записей без сетевых запросов\n"
            f"  {command} --prefix=-kfk- --dry-run --limit 5\n\n"
            "Загрузка всех записей\n"
            f"  {command} --prefix=-kfk-"
        ),
    )
    options = parser.add_argument_group("Параметры")
    options.add_argument("-h", "--help", action="help", help="Показать справку.")
    options.add_argument(
        "--log-dir", type=Path, default=Path(r"C:\kfk"), metavar="КАТАЛОГ",
        help="Искать .log в этом каталоге и его подкаталогах (по умолчанию %(default)s).",
    )
    options.add_argument(
        "--prefix", required=True, metavar="ТЕКСТ",
        help="Обязательный префикс между именем процесса и датой. Разделители задаются вместе с ним.",
    )
    options.add_argument(
        "--url", default="http://localhost:9200", metavar="URL",
        help="REST-адрес Elasticsearch (по умолчанию %(default)s).",
    )
    options.add_argument(
        "--limit", type=int, metavar="ЧИСЛО", help="Максимальное число записей суммарно по всем файлам.",
    )
    options.add_argument(
        "--dry-run", action="store_true", help="Проверить JSON и вывести имена индексов без сетевых запросов.",
    )
    args = parser.parse_args()
    if args.limit is not None and args.limit < 1:
        parser.error("--limit must be positive")

    url = None if args.dry_run else f"{args.url.rstrip('/')}/_bulk?filter_path=items.create.status,items.create.error.type"
    total = 0
    try:
        root = args.log_dir.resolve()
        files = sorted(find_log_files(root))
        if not files:
            raise ValueError(f"No .log files found under {root}")
        for file in files:
            index = index_name(file, args.prefix)
            remaining = None if args.limit is None else args.limit - total
            count = import_file(file, index, url, remaining)
            total += count
            print(f"{file} -> {index} ({count} records)", flush=True)
            if total == args.limit:
                break
    except (OSError, RuntimeError, ValueError) as error:
        parser.exit(1, f"{error}\n")

    verb = "Validated" if args.dry_run else "Processed"
    print(f"{verb} {total} records.")


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    main()
