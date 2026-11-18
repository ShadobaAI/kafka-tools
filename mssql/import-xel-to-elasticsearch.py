import argparse
from base64 import b64encode
from collections.abc import Iterable, Iterator
from contextlib import closing
from hashlib import sha256
from http.client import HTTPConnection, HTTPException, HTTPSConnection
import json
from math import isfinite
import os
from pathlib import Path
import re
from socket import gethostname
from stat import FILE_ATTRIBUTE_REPARSE_POINT
import sys
from typing import Any, NamedTuple
from urllib.parse import urlsplit


DEFAULT_LOG_DIR = Path(r"C:\docker-backups\mssql")
DEFAULT_URL = "http://localhost:9200"
DEFAULT_INDEX = "mssql-xel"
DLL_NAME = "Microsoft.SqlServer.XEvent.Linq.dll"
INSTALL_COMMAND = 'python -m pip install "pythonnet>=3.1,<4"'
MAX_BATCH_EVENTS = 500
MAX_BATCH_BYTES = 5 * 1024 * 1024
SOURCE_ID_SCHEME = "source-v1"
BULK_ACTION = b'{"index":{"_id":"%s"}}' + b"\n"
BULK_ACTION_BYTES = len(BULK_ACTION % b64encode(bytes(sha256().digest_size)))
JsonObject = dict[str, Any]
SourceKey = tuple[str, ...] | None

DATA_TYPES = {
    "statement": "text",
    "batch_text": "text",
    "message": "text",
    "data_stream": "binary",
    "is_intercepted": "boolean",
    "user_defined": "boolean",
    "duration": "unsigned_long",
    "cpu_time": "unsigned_long",
    "logical_reads": "unsigned_long",
    "physical_reads": "unsigned_long",
    "page_server_reads": "unsigned_long",
    "writes": "unsigned_long",
    "row_count": "unsigned_long",
    "spills": "unsigned_long",
    "error_number": "long",
    "request_id": "long",
    "severity": "long",
    "state": "long",
}
ACTION_TYPES = {
    "sql_text": "text",
    "query_hash": "unsigned_long",
    "database_id": "long",
    "session_id": "long",
}
INTEGER_TYPES = {"long", "unsigned_long"}

INDEX_DEFINITION = {
    "mappings": {
        "_meta": {"xel_id_scheme": SOURCE_ID_SCHEME},
        "date_detection": False,
        "dynamic_templates": [
            {
                "xel_fields": {
                    "path_match": ["data.*", "actions.*"],
                    "match_mapping_type": ["string", "long", "double", "boolean"],
                    "mapping": {"type": "keyword", "ignore_above": 4096},
                }
            }
        ],
        "properties": {
            "@timestamp": {"type": "date_nanos"},
            "event_name": {"type": "keyword"},
            "event_package": {"type": "keyword"},
            "file_name": {"type": "keyword"},
            "event_number": {"type": "long"},
            "data": {"properties": {name: {"type": kind} for name, kind in DATA_TYPES.items()}},
            "actions": {"properties": {name: {"type": kind} for name, kind in ACTION_TYPES.items()}},
        },
    }
}


class RussianHelpFormatter(argparse.RawDescriptionHelpFormatter):
    def add_usage(self, usage, actions, groups, prefix=None):
        super().add_usage(usage, actions, groups, prefix or "Использование: ")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Загружает события SQL Server Extended Events (.xel) в Elasticsearch. "
        "Каждое событие сохраняется отдельным документом с полями для поиска и фильтрации.",
        add_help=False,
        allow_abbrev=False,
        formatter_class=RussianHelpFormatter,
        epilog=(
            "Проверка файлов из корня репозитория\n"
            "  python .\\mssql\\import-xel-to-elasticsearch.py --dry-run\n"
            "\n"
            "Загрузка в Elasticsearch\n"
            "  python .\\mssql\\import-xel-to-elasticsearch.py\n"
            "\n"
            "Для чтения .xel нужны 64-разрядный Python 3.11 или новее и установленная SSMS.\n"
            "Команда установки Python.NET\n"
            f"  {INSTALL_COMMAND}"
        ),
    )
    options = parser.add_argument_group("Параметры")
    options.add_argument("-h", "--help", action="help", help="Показать эту справку и выйти.")
    options.add_argument(
        "--log-dir", type=Path, default=DEFAULT_LOG_DIR, metavar="КАТАЛОГ",
        help="Каталог с .xel, включая подкаталоги. По умолчанию %(default)s.",
    )
    options.add_argument(
        "--url", default=DEFAULT_URL, metavar="АДРЕС",
        help="Адрес REST API Elasticsearch. По умолчанию %(default)s.",
    )
    options.add_argument(
        "--index", default=DEFAULT_INDEX, metavar="ИНДЕКС",
        help="Индекс для загрузки событий. По умолчанию %(default)s.",
    )
    options.add_argument(
        "--ssms-dll", type=Path, metavar="ФАЙЛ",
        help=f"Путь к {DLL_NAME} при нестандартной установке SSMS.",
    )
    options.add_argument(
        "--dry-run", action="store_true",
        help="Прочитать файлы и собрать пакеты локально, без запросов к Elasticsearch.",
    )
    source = options.add_mutually_exclusive_group()
    source.add_argument(
        "--source-id", metavar="ИСТОЧНИК",
        help="Постоянное имя источника для повторного импорта после переноса файлов.",
    )
    source.add_argument(
        "--legacy-ids", action="store_true",
        help="Сохранить прежние идентификаторы при повторной загрузке в индекс старого импортера.",
    )
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,254}", args.index):
        parser.exit(2, "Укажите имя индекса строчными латинскими буквами и цифрами. "
                    "Внутри имени также допустимы точка, дефис и подчёркивание.\n")
    if args.source_id is not None:
        args.source_id = args.source_id.strip()
        if not args.source_id:
            parser.exit(2, "Укажите непустое имя источника в --source-id.\n")
    return args


def find_ssms_dll(requested_path: Path | None) -> Path:
    if requested_path is not None:
        if not requested_path.is_file():
            raise FileNotFoundError(f"Библиотека SSMS по пути «{requested_path}» не найдена.")
        return requested_path.resolve()

    for variable in ("ProgramFiles", "ProgramFiles(x86)"):
        install_dir = os.environ.get(variable)
        if install_dir:
            root = Path(install_dir)
            candidates = list(root.glob(f"Microsoft SQL Server Management Studio */*/Common7/IDE/{DLL_NAME}"))
            candidates.extend(root.glob(f"Microsoft SQL Server Management Studio */Common7/IDE/{DLL_NAME}"))
            dll = max(candidates, default=None)
            if dll is not None:
                return dll
    raise FileNotFoundError(f"Библиотека {DLL_NAME} не найдена. Укажите её путь через --ssms-dll.")


def find_xel_files(root: Path) -> list[Path]:
    files = []
    directories = [root]
    while directories:
        with os.scandir(directories.pop()) as entries:
            for entry in entries:
                if entry.is_dir(follow_symlinks=False):
                    # Keep the traversal inside the source tree, including on Windows junctions.
                    attributes = getattr(entry.stat(follow_symlinks=False), "st_file_attributes", 0)
                    if not attributes & FILE_ATTRIBUTE_REPARSE_POINT:
                        directories.append(Path(entry.path))
                elif entry.name.lower().endswith(".xel") and entry.is_file():
                    files.append(Path(entry.path))
    return sorted(files)


class XelReader:
    def __init__(self, assembly_path: Path) -> None:
        try:
            from pythonnet import load
        except ModuleNotFoundError as exc:
            raise RuntimeError(f"Для чтения .xel установите Python.NET командой {INSTALL_COMMAND}") from exc

        load("netfx")
        import clr

        clr.AddReference(str(assembly_path))
        from Microsoft.SqlServer.XEvent import MapValue, XMLData
        from Microsoft.SqlServer.XEvent.Linq import QueryableXEventData
        from System import Array, Byte

        self.query_events = QueryableXEventData
        self.map_type = MapValue
        self.xml_type = XMLData
        self.binary_type = Array[Byte]

    def read_fields(self, fields, types: dict[str, str]) -> tuple[JsonObject, dict[str, int], dict[str, str | None]]:
        values, map_keys, map_labels = {}, {}, {}
        for field in fields:
            name, value = field.Name, field.Value
            if isinstance(value, self.map_type):
                map_keys[name] = value.Key
                if types.get(name) in INTEGER_TYPES:
                    map_labels[name] = value.Value
                    value = value.Key
                else:
                    value = value.Value
            elif isinstance(value, self.xml_type):
                value = value.RawString
            elif isinstance(value, self.binary_type):
                value = b64encode(bytes(value)).decode("ascii")
            elif isinstance(value, float) and not isfinite(value):
                value = str(value)
            elif value is not None and not isinstance(value, (str, int, float, bool)):
                value = str(value)
            values[name] = value
        return values, map_keys, map_labels

    def documents(self, path: Path, file_name: str) -> Iterator[JsonObject]:
        with self.query_events(str(path)) as events:
            for number, event in enumerate(events, 1):
                data, data_keys, data_labels = self.read_fields(event.Fields, DATA_TYPES)
                actions, action_keys, action_labels = self.read_fields(event.Actions, ACTION_TYPES)
                document = {
                    "@timestamp": event.Timestamp.UtcDateTime.ToString("o"),
                    "event_name": event.Name,
                    "event_package": event.Package.Name,
                    "file_name": file_name,
                    "event_number": number,
                    "data": data,
                    "actions": actions,
                    "map_keys": {"data": data_keys, "actions": action_keys},
                }
                if data_labels or action_labels:
                    document["map_labels"] = {"data": data_labels, "actions": action_labels}
                yield document


def json_bytes(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8")


class BulkDocument(NamedTuple):
    file_name: str
    number: int
    timestamp: str
    payload: bytes


def batches(documents: Iterable[JsonObject]) -> Iterator[list[BulkDocument]]:
    batch = []
    size = 0
    for document in documents:
        payload = json_bytes(document)
        entry_size = BULK_ACTION_BYTES + len(payload) + 1
        if batch and (len(batch) >= MAX_BATCH_EVENTS or size + entry_size > MAX_BATCH_BYTES):
            yield batch
            batch = []
            size = 0
        batch.append(BulkDocument(document["file_name"], document["event_number"], document["@timestamp"], payload))
        size += entry_size
    if batch:
        yield batch


def bulk_payload(batch: list[BulkDocument], source: SourceKey) -> bytes:
    lines = []
    for document in batch:
        if source is None:
            # Match the IDs assigned by the previous PowerShell and Python importers.
            identity = f"{document.file_name}\n{document.number}\n{document.timestamp}".encode("utf-8")
        else:
            identity = json_bytes((SOURCE_ID_SCHEME, source, document.file_name, document.number, document.timestamp))
        document_id = b64encode(sha256(identity).digest())
        lines.extend((BULK_ACTION % document_id, document.payload, b"\n"))
    return b"".join(lines)


def select_source(args: argparse.Namespace, root: Path, scheme: str | None) -> SourceKey:
    if args.legacy_ids:
        if scheme is not None:
            raise RuntimeError("--legacy-ids применяется к индексу, созданному прежней версией скрипта.")
        return None
    if args.source_id is not None:
        return ("named", args.source_id)
    if scheme is None:
        if args.index == DEFAULT_INDEX and args.url.rstrip("/") == DEFAULT_URL and root == DEFAULT_LOG_DIR.resolve():
            return None
        raise RuntimeError(
            "Индекс использует прежнюю схему идентификаторов. Для повторной загрузки прежнего источника "
            "укажите --legacy-ids. Для добавления нового источника укажите его имя через --source-id."
        )
    return ("directory", gethostname().casefold(), os.path.normcase(str(root)))


def accepts_dynamic_fields(mapping: JsonObject) -> bool:
    return (
        mapping.get("type", "object") == "object"
        and mapping.get("enabled", True) is True
        and mapping.get("dynamic", True) in (True, "true")
    )


def mapping_conflicts(required: JsonObject, actual: JsonObject, prefix: str = "") -> list[str]:
    properties = actual.get("properties", {})
    conflicts = []
    for name, expected in required.items():
        path = prefix + name
        definition = properties.get(name)
        if definition is None:
            conflicts.append(f"{path} отсутствует")
        elif "properties" in expected:
            if not accepts_dynamic_fields(definition):
                conflicts.append(f"{path} должен быть объектом с динамическими полями")
            else:
                conflicts.extend(mapping_conflicts(expected["properties"], definition, path + "."))
        elif definition.get("type") != expected["type"]:
            conflicts.append(f"{path} должен иметь тип {expected['type']}")
        elif expected["type"] != "binary" and definition.get("index", True) is False:
            conflicts.append(f"{path} должен индексироваться")
        elif expected["type"] not in ("binary", "text") and definition.get("doc_values", True) is False:
            conflicts.append(f"{path} должен поддерживать агрегации")
    return conflicts


def validate_mapping(index: str, mapping: JsonObject) -> str | None:
    expected = INDEX_DEFINITION["mappings"]
    conflicts = mapping_conflicts(expected["properties"], mapping)
    if not accepts_dynamic_fields(mapping):
        conflicts.append("корневое dynamic должно быть true")
    if mapping.get("date_detection") is not False:
        conflicts.append("date_detection должно быть false")
    if mapping.get("dynamic_templates", [])[:1] != expected["dynamic_templates"]:
        conflicts.append("шаблон xel_fields должен быть первым в dynamic_templates")
    source = mapping.get("_source", {})
    if source.get("enabled") is False or source.get("includes") or source.get("excludes"):
        conflicts.append("_source должен сохранять события целиком")
    properties = mapping.get("properties", {})
    for name in ("map_keys", "map_labels"):
        definition = properties.get(name, {})
        if not accepts_dynamic_fields(definition):
            conflicts.append(f"{name} должен быть объектом с динамическими полями")
        for group in ("data", "actions"):
            if not accepts_dynamic_fields(definition.get("properties", {}).get(group, {})):
                conflicts.append(f"{name}.{group} должен быть объектом с динамическими полями")
    scheme = mapping.get("_meta", {}).get("xel_id_scheme")
    if scheme not in (None, SOURCE_ID_SCHEME):
        conflicts.append(f"неизвестная схема идентификаторов xel_id_scheme={scheme}")
    if conflicts:
        raise RuntimeError(f"Маппинг индекса «{index}» несовместим. {'. '.join(conflicts)}.")
    return scheme


def elastic_error_type(error: object) -> str:
    if isinstance(error, dict) and isinstance(error.get("type"), str):
        return error["type"]
    return "unknown_error"


class ElasticsearchRequestError(RuntimeError):
    def __init__(self, method: str, path: str, status: int, error_type: str) -> None:
        self.status = status
        self.error_type = error_type
        super().__init__(f"Запрос Elasticsearch {method} {path} завершился ошибкой HTTP {status} ({error_type}).")


class Elasticsearch:
    def __init__(self, url: str, index: str) -> None:
        address = urlsplit(url)
        if address.scheme not in ("http", "https") or not address.hostname or address.username is not None:
            raise ValueError("Параметр --url должен содержать адрес Elasticsearch в формате http://хост:порт.")
        if address.query or address.fragment:
            raise ValueError("Укажите --url без строки запроса и фрагмента.")
        connect = HTTPSConnection if address.scheme == "https" else HTTPConnection
        self.connection = connect(address.hostname, address.port, timeout=120)
        self.index = index
        self.index_path = f"{address.path.rstrip('/')}/{index}"

    def close(self) -> None:
        self.connection.close()

    def request(
        self, method: str, route: str = "", body: bytes | None = None, content_type: str = "application/json",
    ) -> JsonObject:
        path = self.index_path + route
        try:
            self.connection.request(method, path, body=body, headers={"Content-Type": content_type})
            with self.connection.getresponse() as response:
                status = response.status
                content = response.read()
        except TimeoutError as exc:
            raise RuntimeError(f"Истекло время ожидания ответа Elasticsearch на {method} {path}.") from exc
        except (OSError, HTTPException) as exc:
            raise RuntimeError(f"Сбой связи с Elasticsearch при {method} {path}. {exc}") from exc

        try:
            result = json.loads(content)
        except ValueError as exc:
            raise RuntimeError(f"Ответ Elasticsearch на {method} {path} (HTTP {status}) не содержит JSON.") from exc
        if not isinstance(result, dict):
            raise RuntimeError(f"Некорректный ответ Elasticsearch на {method} {path}.")
        if not 200 <= status < 300:
            raise ElasticsearchRequestError(method, path, status, elastic_error_type(result.get("error")))
        return result

    def get_mapping(self) -> JsonObject | None:
        try:
            result = self.request("GET", "/_mapping")
        except ElasticsearchRequestError as exc:
            if exc.status == 404 and exc.error_type == "index_not_found_exception":
                return None
            raise
        if set(result) != {self.index}:
            raise RuntimeError(f"Укажите имя конкретного индекса. Elasticsearch разрешил «{self.index}» в другой индекс.")
        mapping = result[self.index].get("mappings")
        if not isinstance(mapping, dict):
            raise RuntimeError(f"Elasticsearch вернул некорректный маппинг для «{self.index}».")
        return mapping

    def ensure_index(self, allow_create: bool) -> str | None:
        mapping = self.get_mapping()
        if mapping is None:
            if not allow_create:
                raise RuntimeError(f"Индекс «{self.index}» для повторного импорта с --legacy-ids отсутствует.")
            try:
                result = self.request("PUT", body=json_bytes(INDEX_DEFINITION))
            except ElasticsearchRequestError as exc:
                if exc.status != 400 or exc.error_type != "resource_already_exists_exception":
                    raise
            else:
                if result.get("acknowledged") is not True:
                    raise RuntimeError("Elasticsearch не подтвердил создание индекса.")
            # Check the effective mapping, including templates and a possible concurrent creation.
            mapping = self.get_mapping()
            if mapping is None:
                raise RuntimeError(f"Индекс «{self.index}» отсутствует после запроса на создание.")
        return validate_mapping(self.index, mapping)

    def send_batch(self, payload: bytes, count: int, first_event: int) -> None:
        result = self.request(
            "POST", "/_bulk?filter_path=errors,items.index.status,items.index.error.type",
            payload, "application/x-ndjson",
        )
        items = result.get("items")
        if not isinstance(items, list) or len(items) != count:
            raise RuntimeError(f"Elasticsearch вернул неполный результат для пакета из {count} событий.")
        for number, item in enumerate(items, first_event):
            outcome = item.get("index") if isinstance(item, dict) else None
            status = outcome.get("status") if isinstance(outcome, dict) else None
            if type(status) is not int:
                raise RuntimeError(f"Elasticsearch вернул некорректный результат для события №{number}.")
            if not 200 <= status < 300:
                error_type = elastic_error_type(outcome.get("error"))
                raise RuntimeError(f"Elasticsearch отклонил событие №{number} (HTTP {status}, {error_type}).")
        if result.get("errors") is not False:
            raise RuntimeError("Elasticsearch сообщил об ошибке пакетной загрузки.")

    def refresh(self) -> None:
        result = self.request("POST", "/_refresh")
        if result["_shards"]["failed"]:
            raise RuntimeError("Elasticsearch не смог обновить все шарды индекса.")


def run_import(args: argparse.Namespace) -> None:
    root = args.log_dir.resolve()
    if not root.is_dir():
        raise NotADirectoryError(f"Каталог «{root}» не найден.")
    files = find_xel_files(root)
    if not files:
        raise FileNotFoundError(f"В каталоге «{root}» нет файлов .xel.")

    reader = XelReader(find_ssms_dll(args.ssms_dll))
    elastic = None if args.dry_run else Elasticsearch(args.url, args.index)
    source = select_source(args, root, None if args.legacy_ids else SOURCE_ID_SCHEME)
    index_ready = False
    try:
        total = 0
        for path in files:
            file_name = path.relative_to(root).as_posix()
            count = 0
            try:
                with closing(reader.documents(path, file_name)) as documents:
                    for batch in batches(documents):
                        if elastic is not None and not index_ready:
                            scheme = elastic.ensure_index(allow_create=not args.legacy_ids)
                            source = select_source(args, root, scheme)
                            index_ready = True
                        payload = bulk_payload(batch, source)
                        if elastic is not None:
                            elastic.send_batch(payload, len(batch), batch[0].number)
                        count += len(batch)
            except Exception as exc:
                raise RuntimeError(f"Ошибка обработки файла «{file_name}». {exc}") from exc
            total += count
            print(f"{file_name} — событий {count}", flush=True)
        if elastic is not None:
            if index_ready:
                elastic.refresh()
            print(f"Загружено {total} событий из {len(files)} файлов в индекс «{args.index}».")
        else:
            print(f"Подготовлено {total} событий из {len(files)} файлов для индекса «{args.index}».")
    finally:
        if elastic is not None:
            elastic.close()


def main() -> int:
    args = parse_args()
    try:
        run_import(args)
    except Exception as exc:
        print(f"Ошибка импорта. {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        if not stream.isatty():
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
    sys.exit(main())
