"""Kafka AI desktop entry point (also the frozen, windowless entry point)."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import queue
import sys
import time
import tkinter as tk
from tkinter import filedialog, messagebox

import customtkinter as ctk

from backend import (ACTIONS, ACTION_FIELDS, PARAMETERS, Runner, load_settings, save_settings,
                     settings_path, default_settings, validate, redact)


# Fields: key, title, guidance, file/directory picker. Defaults belong to backend.
FIELDS = {
    "workspace": ("Kafka workspace", "Общий каталог проектов с папками tools, adapter, conversion и tests. Определяет, с каким окружением работать.", "dir"),
    "toolkit": ("Исходный toolkit", "Комплект скриптов и ресурсов для установки. Пусто: <workspace>\\tools\\ai; меняйте только для другого комплекта.", "dir"),
    "project": ("Проверяемый проект", "Корень репозитория для проверки его настроек и готовности. Пусто: проверка относительно выбранного workspace.", "dir"),
    "codex": ("Профиль Codex", "Каталог настроек Codex и MCP. Пусто: CODEX_HOME или стандартный профиль пользователя; укажите путь для другого профиля.", "dir"),
    "node": ("Node.js", "Путь к node.exe версии 18+ для выполнения скриптов. Пусто: поиск через CODE_INDEX_NODE, Program Files и PATH.", "file"),
    "java": ("Java для BSL LS", "Путь к java.exe версии 25+ для языкового сервера BSL. Пусто: BSL_LANGUAGE_SERVER_JAVA или настройка BSL LS; явный путь должен совпадать с ней.", "file"),
    "indexer": ("Локальный bsl-indexer", "Готовый исполняемый файл индексатора BSL вместо загрузки релиза. Пусто: скрипт проверит последний релиз и при необходимости загрузит его.", "file"),
    "jar": ("BSL Language Server", "Готовый JAR языкового сервера BSL вместо загрузки релиза. Пусто: скрипт проверит последний релиз и при необходимости загрузит его.", "file"),
    "state": ("Данные OpenViking", "Каталог данных и конфигурации OpenViking. Пусто: KAFKA_OPENVIKING_STATE_DIR или папка openviking-docker в профиле Codex.", "dir"),
    "ollama": ("Внешний Ollama", "Адрес сервера моделей, например http://localhost:11434, без логина, пароля и пути. Пусто: KAFKA_OLLAMA_URL или Ollama в Docker.", None),
    "index_timeout": ("Ожидание индексов, с", "Сколько ждать готовности code-index после запуска. 60–3600 с; обычно 1800. Увеличьте для больших репозиториев.", None),
    "mcp_timeout": ("Ожидание MCP, с", "Сколько ждать успешной проверки готовности MCP. 60–3600 с; обычно 600. Увеличьте при медленном запуске сервисов.", None),
}
FORM_KEYS = {action: tuple(key for key in FIELDS if key in keys) for action, keys in ACTION_FIELDS.items()}
SWITCHES = {
    "install": (("configuration_only", "Только конфигурация", "Настроить Codex, правила, Git-хуки и навыки без установки runtime и перестройки индексов. Готовность MCP не проверяется; обычно выключено."),
                ("skip_viking", "Пропустить OpenViking runtime", "Пропустить развёртывание OpenViking в Docker и начальную синхронизацию. Остальная установка продолжается; обычно выключено."),
                ("skip_daemon", "Не запускать daemon", "Оставить запуск code-index на потом. При полной установке старые индексы всё равно удаляются, готовность не проверяется; обычно выключено."),
                ("gpu", "GPU для Ollama", "Включить NVIDIA GPU для Ollama в Docker. Нужна поддержка GPU в Docker; для внешнего Ollama не применяется. Обычно выключено.")),
    "viking": (("rebuild", "Полная перестройка", "Удалить производный Git-индекс и построить заново с подтверждением. Выключено: обновить только изменения. Выбор не сохраняется."),),
    "doctor": (("human", "Отчёт с пояснениями", "Показать читаемый отчёт doctor (--human); включено по умолчанию. Выключите для JSON, удобного для автоматической обработки."),),
}
FIELD_HINTS = {
    "code": {"toolkit": "Комплект скриптов и ресурсов для обновления code-index. Пусто: <workspace>\\tools\\ai."},
    "doctor": {"node": "Путь к node.exe версии 18+ для проверки окружения. Пусто: поиск в PATH."},
    "viking": {
        "node": "Путь к node.exe версии 18+ для синхронизации OpenViking. Пусто: поиск в PATH.",
        "state": "Каталог существующих данных OpenViking. Пусто: KAFKA_OPENVIKING_STATE_DIR или путь из установленного MCP.",
    },
}
DESCRIPTIONS = {
    "install": "Подготовка runtime, конфигурации и индексов. Интерактивные вопросы откроются в консоли.",
    "doctor": "Проверка настроек и готовности MCP. Сервисы и индексы не обновляются.",
    "code": "Обновление bsl-indexer и полная перестройка Kafka-индексов. Отключите code-index в Codex перед запуском.",
    "viking": "Синхронизация committed HEAD. По умолчанию обновляются только изменения.",
}


class FormEntry(ctk.CTkEntry):
    def destroy(self):
        # CustomTkinter 5.2.2 leaves this trace installed after destroying CTkEntry.
        # Rebuilding a form must not leave callbacks pointing at dead Tk widgets.
        if self._textvariable_callback_name:
            self._textvariable.trace_remove("write", self._textvariable_callback_name)
            self._textvariable_callback_name = ""
        super().destroy()


class App(ctk.CTk):
    def __init__(self, *, fixture=False, config=None):
        self.config_path = config or settings_path()
        settings_error = None
        try:
            settings = load_settings(self.config_path)
        except (OSError, ValueError) as error:
            settings = default_settings()
            settings_error = str(error)
        ctk.set_appearance_mode(settings["theme"])
        ctk.set_default_color_theme("blue")
        super().__init__()
        self.title("Kafka AI · Управление окружением" + (" · ПРОВЕРКА СБОРКИ" if fixture else ""))
        self.geometry("1140x840")
        self.minsize(900, 680)
        self.runner = Runner(fixture=fixture)
        self.fixture = fixture
        self.action = "install"
        self.variables = {key: (tk.BooleanVar(value=value) if type(value) is bool else tk.StringVar(value=value))
                          for key, value in settings.items()}
        self.controls = []
        self.started = None
        self.log_lines = 0
        self.failures = []
        self.run_values = None
        self._autosave_after = None
        self._autosave_traces = []
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)

        sidebar = ctk.CTkFrame(self, width=220, corner_radius=0,
                               fg_color=("#e9eef5", "#17212f"))
        sidebar.grid(row=0, column=0, sticky="nsew")
        sidebar.grid_propagate(False)
        ctk.CTkLabel(sidebar, text="KAFKA / AI", font=ctk.CTkFont(size=25, weight="bold")).pack(padx=20, pady=(30, 4), anchor="w")
        ctk.CTkLabel(sidebar, text="Окружение разработчика", text_color=("#526075", "#a6b2c5")).pack(padx=20, pady=(0, 30), anchor="w")
        self.navigation = {}
        for key, label in ACTIONS.items():
            button = ctk.CTkButton(sidebar, text=label, anchor="w", height=44, border_width=1,
                                   command=lambda k=key: self.select(k))
            button.pack(fill="x", padx=12, pady=5)
            self.navigation[key] = button
        ctk.CTkLabel(sidebar, text="Оформление").pack(padx=20, pady=(35, 6), anchor="w")
        self.theme = ctk.CTkOptionMenu(sidebar, values=["System", "Light", "Dark"],
                                      variable=self.variables["theme"], command=self.change_theme)
        self.theme.pack(padx=20, fill="x")
        ctk.CTkLabel(sidebar, text="System · как в Windows\nLight · светлая\nDark · тёмная\nВыбор сохраняется.", justify="left",
                     text_color=("#536174", "#a6b2c5")).pack(padx=20, pady=8, anchor="w")
        self.save_button = ctk.CTkButton(sidebar, text="Сохранить настройки", command=self.save)
        self.save_button.pack(side="bottom", padx=14, pady=20, fill="x")
        self.settings_notice = ctk.CTkLabel(sidebar, text="Автосохранение включено", wraplength=192, justify="left")
        self.settings_notice.pack(side="bottom", padx=14, pady=4, fill="x")
        ctk.CTkButton(sidebar, text="Сохранить журнал…", command=self.export_log).pack(side="bottom", padx=14, pady=4, fill="x")

        content = ctk.CTkFrame(self, fg_color="transparent")
        content.grid(row=0, column=1, sticky="nsew", padx=24, pady=20)
        content.grid_columnconfigure(0, weight=1)
        content.grid_rowconfigure(2, weight=3)
        content.grid_rowconfigure(6, weight=2)
        self.heading = ctk.CTkLabel(content, font=ctk.CTkFont(size=26, weight="bold"), anchor="w")
        self.heading.grid(row=0, column=0, sticky="ew")
        self.description = ctk.CTkLabel(content, anchor="w", justify="left", wraplength=780)
        self.description.grid(row=1, column=0, sticky="ew", pady=(8, 16))
        self.form = ctk.CTkScrollableFrame(content, corner_radius=12)
        self.form.grid(row=2, column=0, sticky="nsew")
        self.form.grid_columnconfigure(0, weight=1)
        bar = ctk.CTkFrame(content, fg_color="transparent")
        bar.grid(row=3, column=0, sticky="ew", pady=(15, 8))
        bar.grid_columnconfigure(0, weight=1)
        self.status = ctk.CTkLabel(bar, text="Готово к запуску", anchor="w", wraplength=560, justify="left")
        self.status.grid(row=0, column=0, sticky="ew")
        self.run_button = ctk.CTkButton(bar, text="Запустить", height=42, command=self.launch)
        self.run_button.grid(row=0, column=1, padx=(10, 0))
        self.progress = ctk.CTkProgressBar(content, height=5, mode="indeterminate")
        self.progress.grid(row=4, column=0, sticky="ew")
        self.progress.set(0)
        self.elapsed = ctk.CTkLabel(content, text="Журнал текущего сеанса • секретные параметры не сохраняются", anchor="w")
        self.elapsed.grid(row=5, column=0, sticky="ew", pady=(12, 4))
        self.log = ctk.CTkTextbox(content, height=170, font=ctk.CTkFont(family="Consolas", size=12), state="disabled")
        self.log.grid(row=6, column=0, sticky="nsew")
        self.select("install")
        for key, variable in self.variables.items():
            if key != "rebuild":
                self._autosave_traces.append((variable, variable.trace_add("write", self.schedule_save)))
        if settings_error:
            self.settings_notice.configure(text="Кэш недоступен — см. журнал")
            self.append("Не удалось загрузить или создать кэш настроек: " + settings_error)
        self.protocol("WM_DELETE_WINDOW", self.close)
        self.after(50, self.poll)

    def values(self):
        return {key: var.get().strip() if isinstance(var, tk.StringVar) else var.get()
                for key, var in self.variables.items()}

    def change_theme(self, value):
        ctk.set_appearance_mode(value)

    def select(self, action):
        if self.runner.busy:
            return
        self.action = action
        self.heading.configure(text=ACTIONS[action])
        self.description.configure(text=DESCRIPTIONS[action])
        for key, button in self.navigation.items():
            selected = key == action
            text_color = ("#ffffff", "#ffffff") if selected else ("#172b4d", "#f1f5f9")
            button.configure(
                fg_color=("#245ec7", "#245ec7") if selected else ("#ffffff", "#263347"),
                text_color=text_color,
                text_color_disabled=text_color,
                hover_color=("#1c4da6", "#1c4da6") if selected else ("#dce8fa", "#36465e"),
                border_color=("#245ec7", "#75a7ff") if selected else ("#b8c7da", "#53647b"),
            )
        for widget in self.form.winfo_children():
            widget.destroy()
        self.controls = []
        row = 0
        for key in FORM_KEYS[action]:
            title, hint, picker = FIELDS[key]
            hint = FIELD_HINTS.get(action, {}).get(key, hint)
            parameter = PARAMETERS.get(action, {}).get(key)
            if parameter:
                hint += f"  Параметр: -{parameter}."
            frame = ctk.CTkFrame(self.form, fg_color="transparent")
            frame.grid(row=row, column=0, sticky="ew", padx=10, pady=7)
            frame.grid_columnconfigure(0, weight=1)
            ctk.CTkLabel(frame, text=title, anchor="w", font=ctk.CTkFont(weight="bold")).grid(row=0, column=0, sticky="w")
            entry = FormEntry(frame, textvariable=self.variables[key], height=34)
            entry.grid(row=1, column=0, sticky="ew")
            self.controls.append(entry)
            if picker:
                button = ctk.CTkButton(frame, text="Обзор…", width=82,
                                       command=lambda k=key, p=picker: self.browse(k, p))
                button.grid(row=1, column=1, padx=(8, 0))
                self.controls.append(button)
            ctk.CTkLabel(frame, text=hint, text_color=("#536174", "#a6b2c5"),
                         anchor="w", justify="left", wraplength=650).grid(row=2, column=0, columnspan=2, sticky="ew")
            row += 1
        for key, title, hint in SWITCHES.get(action, ()):
            parameter = PARAMETERS.get(action, {}).get(key)
            if parameter:
                hint += f"  -{parameter}."
            check = ctk.CTkCheckBox(self.form, text=title, variable=self.variables[key])
            check.grid(row=row, column=0, sticky="w", padx=12, pady=(14, 2))
            self.controls.append(check)
            ctk.CTkLabel(self.form, text=hint, text_color=("#536174", "#a6b2c5"), anchor="w", justify="left", wraplength=650).grid(
                row=row + 1, column=0, sticky="ew", padx=12)
            row += 2

    def browse(self, key, kind):
        value = filedialog.askdirectory(parent=self) if kind == "dir" else filedialog.askopenfilename(parent=self)
        if value:
            self.variables[key].set(value)

    def append(self, text):
        self.log.configure(state="normal")
        lines = redact(text).splitlines() or [""]
        self.log.insert("end", "\n".join(lines) + "\n")
        self.log_lines += len(lines)
        if self.log_lines > 2500:
            self.log.delete("1.0", f"{self.log_lines - 2000 + 1}.0")
            self.log_lines = 2000
        self.log.see("end")
        self.log.configure(state="disabled")

    def save(self):
        try:
            save_settings(self.config_path, self.values())
            self.settings_notice.configure(text="Сохранено " + time.strftime("%H:%M:%S"))
            self.append("Несекретные настройки сохранены.")
        except (OSError, ValueError) as error:
            messagebox.showerror("Настройки не сохранены", str(error), parent=self)

    def schedule_save(self, *_):
        if self._autosave_after is not None:
            self.after_cancel(self._autosave_after)
        self.settings_notice.configure(text="Сохранение изменений…")
        self._autosave_after = self.after(600, self.autosave)

    def autosave(self):
        self._autosave_after = None
        try:
            save_settings(self.config_path, self.values())
            self.settings_notice.configure(text="Сохранено " + time.strftime("%H:%M:%S"))
        except (OSError, ValueError) as error:
            # Incomplete input must not open a modal dialog while the user types.
            self.settings_notice.configure(text="Не сохранено: " + redact(str(error)))

    def destroy(self):
        if self._autosave_after is not None:
            self.after_cancel(self._autosave_after)
            self._autosave_after = None
        for variable, callback in self._autosave_traces:
            variable.trace_remove("write", callback)
        self._autosave_traces.clear()
        super().destroy()

    def export_log(self):
        path = filedialog.asksaveasfilename(parent=self, title="Сохранить журнал", defaultextension=".txt",
                                          initialfile="kafka-ai-log.txt", filetypes=[("Текст UTF-8", "*.txt")])
        if path:
            try:
                Path(path).write_text(redact(self.log.get("1.0", "end")), encoding="utf-8-sig")
            except OSError as error:
                messagebox.showerror("Журнал не сохранён", str(error), parent=self)

    def confirm(self, values):
        if self.action == "code" or (self.action == "install" and not values["configuration_only"]):
            return messagebox.askyesno("Перестроить Kafka-индексы?",
                f"Workspace: {values['workspace']}\n\n"
                "Штатный скрипт остановит code-index и удалит Kafka .code-index для перестройки. "
                "Поиск будет недоступен до её завершения. Отключите активные code-index клиенты.\n"
                + ("С выбранным SkipDaemonStart индексы останутся удалёнными до ручного запуска daemon.\n" if values["skip_daemon"] and self.action == "install" else "")
                + "\nПродолжить?",
                default="no", icon="warning", parent=self)
        if self.action == "viking" and values["rebuild"]:
            return messagebox.askyesno("Перестроить OpenViking?",
                f"Workspace: {values['workspace']}\n\nУдалить производный Git-индекс и построить его заново? "
                "Это может занять длительное время.", default="no", icon="warning", parent=self)
        return True

    def launch(self):
        if self.runner.busy:
            return
        values = self.values()
        try:
            validate(values, self.action)
            if not self.confirm(values):
                self.append("Запуск отменён до выполнения скрипта.")
                return
        except (OSError, ValueError) as error:
            messagebox.showerror("Проверьте параметры", str(error), parent=self)
            return
        try:
            save_settings(self.config_path, values)
        except (OSError, ValueError) as error:
            if not messagebox.askyesno("Настройки не сохранены", f"{error}\n\nЗапустить с текущими параметрами без сохранения?", parent=self):
                return
        self.started = time.monotonic()
        self.run_values = values
        self.failures.clear()
        self.status.configure(text="Подготовка запуска…")
        self.append(f"\n{time.strftime('%H:%M:%S')} — {ACTIONS[self.action]}" + (" [ПРОВЕРКА СБОРКИ]" if self.fixture else ""))
        self.set_busy(True)
        try:
            self.runner.start(values, self.action)
        except Exception as error:
            self.started = None
            self.set_busy(False)
            self.status.configure(text="Ошибка запуска")
            self.append("ОШИБКА: " + str(error))

    def set_busy(self, busy):
        for widget in [*self.controls, *self.navigation.values(), self.run_button, self.save_button]:
            widget.configure(state="disabled" if busy else "normal")
        if busy:
            self.progress.start()
        else:
            self.progress.stop()
            self.progress.set(0)

    def poll(self):
        # Bounded drain: even a verbose child cannot starve Tk's event loop.
        for _ in range(100):
            try:
                kind, value = self.runner.events.get_nowait()
            except queue.Empty:
                break
            if kind == "done":
                self.runner.busy = False
                self.set_busy(False)
                partial = self.action == "install" and self.run_values and any(
                    self.run_values[key] for key in ("configuration_only", "skip_daemon", "skip_viking"))
                self.status.configure(text=("Выполнено с пропуском проверок" if partial else "Успешно завершено")
                                      if value == 0 else "Не завершено — см. журнал")
                self.append("Операция завершена." if value == 0 else "Операция завершилась с ошибкой.")
                self.started = None
            elif kind == "stage":
                self.status.configure(text=value[:240])
                self.append("Этап: " + value)
            else:
                self.append(("ОШИБКА: " if kind == "error" else "") + value)
                if kind == "error":
                    self.failures.append(value)
        if self.started:
            self.elapsed.configure(text=f"Журнал • прошло {int(time.monotonic() - self.started)} с • операция выполняется")
        elif not self.runner.busy:
            self.elapsed.configure(text="Журнал текущего сеанса • последние 2500 строк")
        self.after(50, self.poll)

    def report_callback_exception(self, exc_type, error, traceback):
        # Tk otherwise writes to stderr, which is absent in a --windowed build.
        self.append("Ошибка интерфейса: " + str(error))
        messagebox.showerror("Ошибка интерфейса", redact(str(error)), parent=self)

    def close(self):
        if self.runner.busy:
            messagebox.showinfo("Операция выполняется", "Дождитесь завершения. Для установщика проверьте открытое окно консоли. "
                                "Прерывание во время перестройки может оставить индексы неготовыми.", parent=self)
            return
        try:
            save_settings(self.config_path, self.values())
        except (OSError, ValueError) as error:
            if not messagebox.askyesno("Настройки не сохранены", f"{error}\n\nЗакрыть без сохранения?", parent=self):
                return
        self.destroy()


def fixture_worker(action):
    # Only this internal fixture executes in --smoke-test. No script imports.
    if sys.stdout is not None:
        sys.stdout.reconfigure(encoding="utf-8")
    def write(text):
        if sys.stdout is not None:
            print(text, flush=True)
        else:
            # A --windowed executable has no Python stdout, but Popen supplied a pipe.
            import ctypes
            from ctypes import wintypes
            kernel = ctypes.WinDLL("kernel32", use_last_error=True)
            kernel.GetStdHandle.argtypes = [wintypes.DWORD]
            kernel.GetStdHandle.restype = wintypes.HANDLE
            kernel.WriteFile.argtypes = [wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD,
                                        ctypes.POINTER(wintypes.DWORD), ctypes.c_void_p]
            data = (text + "\n").encode("utf-8")
            written = wintypes.DWORD()
            if not kernel.WriteFile(kernel.GetStdHandle(-11), data, len(data), ctypes.byref(written), None):
                raise ctypes.WinError(ctypes.get_last_error())
    for step in range(1, 4):
        write(f"==> {step}/3. Демонстрация {action}: этап {step}")
        time.sleep(.15)
    write("Проверочный процесс завершён; сервисы и индексы не изменялись.")


def smoke(app, report):
    """Exercise real Tk widgets and subprocess transport, replacing only operations/dialogs."""
    def unexpected_error(title, message, **kwargs):
        raise AssertionError(f"Unexpected dialog: {title}: {message}")
    messagebox.showerror = unexpected_error
    checks = []
    actions = iter(ACTIONS)
    original_confirm = app.confirm
    app.confirm = lambda values: True
    deadline = time.monotonic() + 30
    beats = [0]
    failure_test = [False]
    recovery_test = [False]
    confirmations_checked = [False]
    autosave_checked = [False]
    previous_timeout = app.variables["index_timeout"].get()
    assert app.config_path.is_file(), "Defaults cache was not created on startup"
    app.variables["index_timeout"].set("1801")

    def heartbeat():
        beats[0] += 1
        app.after(20, heartbeat)

    def step():
        try:
            if time.monotonic() > deadline:
                raise RuntimeError("GUI smoke timeout")
            if not autosave_checked[0]:
                assert load_settings(app.config_path)["index_timeout"] == "1801", "Changes were not autosaved"
                app.variables["index_timeout"].set(previous_timeout)
                autosave_checked[0] = True
            if not confirmations_checked[0]:
                original_dialog = messagebox.askyesno
                original_values = app.values()
                prompts = []
                try:
                    messagebox.askyesno = lambda *args, **kwargs: prompts.append(kwargs) or False
                    app.confirm = original_confirm
                    app.variables["configuration_only"].set(False)
                    app.variables["skip_daemon"].set(True)
                    app.variables["rebuild"].set(True)
                    for destructive_action in ("install", "code", "viking"):
                        app.select(destructive_action)
                        app.launch()
                        assert not app.runner.busy, "Rejected confirmation started a process"
                    assert len(prompts) == 3 and all(item["default"] == "no" for item in prompts)
                    app.select("install")
                    app.variables["configuration_only"].set(True)
                    assert original_confirm(app.values()), "Configuration-only unexpectedly rebuilds indexes"
                    confirmations_checked[0] = True
                finally:
                    messagebox.askyesno = original_dialog
                    app.confirm = lambda values: True
                    for key, value in original_values.items():
                        app.variables[key].set(value)
            if app.runner.busy:
                assert not app.runner.start(app.values(), app.action), "Parallel start was accepted"
                app.after(70, step)
                return
            if failure_test[0] and not recovery_test[0]:
                assert app.failures, "Failed process was reported as successful"
                assert "Не завершено" in app.status.cget("text")
                app.runner.fixture_exit_code = 0
                app.launch()
                recovery_test[0] = True
                app.after(70, step)
                return
            assert not app.failures, str(app.failures)
            action = next(actions, None)
            if action:
                for theme in ("Light", "Dark"):
                    app.variables["theme"].set(theme)
                    app.change_theme(theme)
                    app.update_idletasks()
                app.select(action)
                for field in FIELDS:
                    assert len(app.variables[field].trace_info()) == 1 + int(field in FORM_KEYS[action]), "Stale form callbacks"
                app.launch()
                assert app.runner.busy, "Operation did not start"
                checks.append(action)
                app.after(70, step)
                return
            if not failure_test[0]:
                app.select("doctor")
                app.runner.fixture_exit_code = 7
                app.launch()
                failure_test[0] = True
                app.after(70, step)
                return
            assert beats[0] >= 20, "Tk event loop did not remain responsive"
            journal = app.log.get("1.0", "end")
            for completed in checks:
                assert f"1/3. Демонстрация {completed}: этап 1" in journal, "Cyrillic subprocess output corrupted"
            assert "Проверочный процесс завершён; сервисы и индексы не изменялись." in journal
            assert "\ufffd" not in journal, "Unicode replacement characters in journal"
            embedded_runtime = {}
            if getattr(sys, "frozen", False):
                bundle = Path(sys._MEIPASS)
                embedded_runtime = {
                    "python": bool(list(bundle.glob("python3*.dll"))),
                    "tcl": (bundle / "_tcl_data/init.tcl").is_file(),
                    "tk": (bundle / "_tk_data/tk.tcl").is_file(),
                    "theme": (bundle / "customtkinter/assets/themes/blue.json").is_file(),
                }
                assert all(embedded_runtime.values()), "Embedded runtime is incomplete"
            app.confirm = original_confirm
            report.write_text(json.dumps({"ok": True, "actions": checks, "heartbeats": beats[0],
                                         "themes": ["Light", "Dark"], "cyrillic": True,
                                         "error_recovery": recovery_test[0],
                                         "confirmations": confirmations_checked[0],
                                         "embedded_runtime": embedded_runtime,
                                         "settings_cache": autosave_checked[0],
                                         "frozen": bool(getattr(sys, "frozen", False))}), encoding="utf-8")
            app.destroy()
        except Exception as error:
            report.write_text(json.dumps({"ok": False, "error": str(error)}), encoding="utf-8")
            app.destroy()
    heartbeat()
    app.after(1000, step)


def main():
    parser = argparse.ArgumentParser(description="Kafka AI desktop")
    parser.add_argument("--smoke-test", type=Path, metavar="REPORT", help="Безопасная GUI-проверка с JSON-отчётом")
    parser.add_argument("--fixture-worker", choices=ACTIONS, help=argparse.SUPPRESS)
    parser.add_argument("--fixture-exit-code", type=int, choices=(0, 7), default=0, help=argparse.SUPPRESS)
    parser.add_argument("--workspace", type=Path)
    args = parser.parse_args()
    if args.fixture_worker:
        fixture_worker(args.fixture_worker)
        raise SystemExit(args.fixture_exit_code)
    if args.smoke_test:
        args.smoke_test.parent.mkdir(parents=True, exist_ok=True)
    app = App(fixture=bool(args.smoke_test),
              config=args.smoke_test.with_suffix(".settings.env") if args.smoke_test else None)
    if args.workspace:
        app.variables["workspace"].set(str(args.workspace.resolve()))
    if args.smoke_test:
        smoke(app, args.smoke_test)
    app.mainloop()


if __name__ == "__main__":
    main()
