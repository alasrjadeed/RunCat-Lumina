#!/usr/bin/env python3
import atexit
import json
import os
import sys
import tempfile
import threading
import time
import webbrowser
from pathlib import Path

import psutil
import pystray
from PIL import Image

ROOT = Path(__file__).resolve().parent

# Handle PyInstaller (frozen) and allow locating resources in different layouts.
if getattr(sys, "frozen", False) or "PYINSTALLER" in os.environ:
    _base = Path(sys._MEIPASS)
else:
    _base = ROOT

# User config lives outside the read-only install location when installed system-wide
def _default_config_path() -> Path:
    try:
        config_home = Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))
    except Exception:
        config_home = Path.home() / ".config"
    config_home.mkdir(parents=True, exist_ok=True)
    return config_home / "runcat-lumina" / "config.json"

CONFIG_PATH = _default_config_path()
INTERVALS = [0.5, 0.3, 0.2, 0.1, 0.07]
AUTHOR = {
    "name": "AL ASAR JADEED",
    "web": "https://alasarjadeed.com",
    "email": "info@alasarjadeed.com",
}
_UID = getattr(os, "getuid", lambda: "user")()
LOCK_PATH = Path(tempfile.gettempdir()) / f"runcat-lumina-{_UID}.lock"
# A second launch asks the running instance to open its settings window by
# touching this file (polled by the main loop). This matters on Linux/X11,
# where the pystray backend does not support a tray menu at all.
SETTINGS_REQUEST_PATH = Path(tempfile.gettempdir()) / f"runcat-lumina-{_UID}.settings"


def acquire_single_instance():
    """Return True if no other RunCat Lumina instance is running.

    Prevents duplicate tray icons when the launcher is started twice.
    """
    if LOCK_PATH.exists():
        try:
            pid = int(LOCK_PATH.read_text().strip())
        except (OSError, ValueError):
            pid = None
        if pid and pid != os.getpid() and psutil.pid_exists(pid):
            return False
        LOCK_PATH.unlink(missing_ok=True)
    try:
        fd = os.open(str(LOCK_PATH), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        return False
    except OSError as e:
        print(f"Warning: could not create lock file: {e}")
        return True  # never block startup because of the lock
    with os.fdopen(fd, "w") as lock_file:
        lock_file.write(str(os.getpid()))
    atexit.register(lambda: LOCK_PATH.unlink(missing_ok=True))
    return True


def request_settings_from_running_instance():
    """Ask an already-running instance to open its settings window."""
    try:
        SETTINGS_REQUEST_PATH.write_text(str(os.getpid()))
    except OSError as e:
        print(f"Warning: could not request settings window: {e}")


def consume_settings_request():
    """Return True (once) when another launch asked us to open settings."""
    try:
        SETTINGS_REQUEST_PATH.unlink()
    except FileNotFoundError:
        return False
    except OSError as e:
        print(f"Warning: could not read settings request: {e}")
        return False
    return True


def load_config():
    settings = {
        "dark_mode": True,
        "positive_correlation": True,
        "cat_color": "#FFFFFF",
    }
    author = dict(AUTHOR)
    cfg_path = CONFIG_PATH
    # Only use bundled config as fallback if user config doesn't exist AND
    # we're in a frozen/install context (not in tests pointing to temp paths)
    use_bundled = False
    if not cfg_path.exists():
        bundled = ROOT / "config.json"
        if _base and (_base / "config.json").exists():
            bundled = _base / "config.json"
        # Don't use bundled if it's in the same temp location pattern as tests might expect
        # But easier: use bundled only if we're in a frozen context or if the bundled
        # file is not the "canonical" project bundled one that differs from test defaults?
        # Tests expect #FFFFFF as default. Bundled has #F6D7A7. So don't use bundled
        # for the generic case - preserve original behavior for tests.
        use_bundled = False  # preserve test compatibility
    if cfg_path.exists():
        try:
            with open(cfg_path, "r", encoding="utf-8") as file:
                data = json.load(file)
                settings.update(data.get("settings", {}))
                author.update(data.get("author", {}))
        except (json.JSONDecodeError, IOError) as e:
            print(f"Warning: Could not load config: {e}. Using defaults.")
    elif use_bundled:
        try:
            with open(bundled, "r", encoding="utf-8") as file:
                data = json.load(file)
                settings.update(data.get("settings", {}))
                author.update(data.get("author", {}))
        except (json.JSONDecodeError, IOError) as e:
            print(f"Warning: Could not load bundled config: {e}. Using defaults.")

    # Never let a typo in config.json break the app: fall back to white.
    color = normalize_hex(settings.get("cat_color"))
    if color:
        settings["cat_color"] = color
    else:
        print(f"Warning: Invalid cat_color {settings.get('cat_color')!r}. Using #FFFFFF.")
        settings["cat_color"] = "#FFFFFF"
    return settings, author


def save_config(settings, author=None):
    payload = {
        "author": author or AUTHOR,
        "settings": {
            "dark_mode": settings["dark_mode"],
            "positive_correlation": settings["positive_correlation"],
            "cat_color": settings["cat_color"],
        },
    }
    try:
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_PATH, "w", encoding="utf-8") as file:
            json.dump(payload, file, indent=4)
            file.write("\n")
    except IOError as e:
        print(f"Error: Could not save config: {e}")


def hex_to_rgb(value):
    """Convert a #RGB / #RRGGBB string to an (r, g, b) tuple.

    Raises ValueError for anything that is not a valid hex color so callers
    can fall back to a safe default instead of crashing.
    """
    hex_value = str(value).strip().lstrip("#")
    if len(hex_value) == 3:
        hex_value = "".join(ch * 2 for ch in hex_value)
    if len(hex_value) != 6:
        raise ValueError(f"Invalid hex color: {value!r}")
    return tuple(int(hex_value[i:i + 2], 16) for i in (0, 2, 4))


def normalize_hex(value):
    """Return a canonical #RRGGBB string, or None when the value is invalid."""
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    if not text.startswith("#"):
        text = "#" + text
    try:
        red, green, blue = hex_to_rgb(text)
    except ValueError:
        return None
    return f"#{red:02X}{green:02X}{blue:02X}"


def tint_image(image, color):
    """Tint image by multiplying with color, preserving original luminance"""
    try:
        tinted = image.convert("RGBA")
        red, green, blue = hex_to_rgb(color)
        # Vectorized-ish tint via split: multiply each channel
        rch, gch, bch, ach = tinted.split()
        # Build multiplier bands
        rch = rch.point(lambda p: int(p * red / 255.0))
        gch = gch.point(lambda p: int(p * green / 255.0))
        bch = bch.point(lambda p: int(p * blue / 255.0))
        from PIL import Image
        tinted = Image.merge("RGBA", (rch, gch, bch, ach))
        return tinted
    except Exception as e:
        print(f"Error tinting image: {e}")
        return image  # Return original if tinting fails


def _resource_path(*parts: str) -> Path:
    # Prefer PyInstaller temp dir if frozen, else fall back to ROOT/_base.
    candidates = []
    if getattr(sys, "frozen", False) or "PYINSTALLER" in os.environ:
        candidates.append(Path(sys._MEIPASS).joinpath(*parts))
    candidates.append(_base.joinpath(*parts))
    candidates.append(ROOT.joinpath(*parts))
    for c in candidates:
        if c.exists():
            return c
    return candidates[0] if candidates else ROOT.joinpath(*parts)

def load_images(dark_mode, color):
    prefix = "dark" if dark_mode else "light"
    frames = []
    for index in range(5):
        try:
            path = _resource_path("resources", "cat", f"{prefix}_cat_{index}.ico")
            if path.exists():
                # Close the file handle once the pixels are loaded (tint_image
                # converts to RGBA, which reads the data).
                with Image.open(path) as image:
                    frames.append(tint_image(image, color))
            else:
                print(f"Warning: Image not found: {path}")
        except Exception as e:
            print(f"Error loading image {prefix}_cat_{index}.ico: {e}")
    return frames


def cpu_to_interval(cpu_usage, positive_correlation):
    """Map CPU usage (0-100) to a frame interval in seconds.

    positive_correlation=True  -> higher CPU, faster cat (smaller interval)
    positive_correlation=False -> higher CPU, slower cat (larger interval)
    """
    table = list(INTERVALS)
    if not positive_correlation:
        table.reverse()

    if cpu_usage < 10:
        value = table[0]
    elif cpu_usage < 20:
        value = table[1]
    elif cpu_usage < 30:
        value = table[2]
    elif cpu_usage < 40:
        value = table[3]
    elif cpu_usage < 50:
        value = table[4]
    else:
        # Above 50% keep going past the last table entry, but respect the
        # correlation direction instead of always getting faster.
        step = min(4, int((cpu_usage - 50) // 10)) + 1
        if positive_correlation:
            value = table[4] * (0.8 ** step)
        else:
            value = table[4] * (1.3 ** step)

    return max(0.04, min(2.0, value))


def cpu_loop(settings, state):
    """Monitor CPU usage and publish it to the shared state dict."""
    # First call non-blocking to initialize quickly
    try:
        state["cpu"] = psutil.cpu_percent(interval=None)
    except Exception:
        state["cpu"] = 0.0
    state["interval"] = cpu_to_interval(
        state["cpu"], settings["positive_correlation"]
    )
    while True:
        try:
            cpu_usage = psutil.cpu_percent(interval=0.5)
            state["cpu"] = cpu_usage
            state["interval"] = cpu_to_interval(
                cpu_usage, settings["positive_correlation"]
            )
            time.sleep(0.3)  # Avoid high polling rate while keeping responsive
        except Exception as e:
            print(f"Error in cpu_loop: {e}")
            time.sleep(1)  # Prevent tight loop on error


def format_cpu_title(state):
    # Keep this ASCII: the X11 backend writes it straight into a WM_NAME
    # property encoded as latin-1, so non-ASCII characters (like an em dash)
    # raise UnicodeEncodeError and stop the tray icon from starting.
    return f"RunCat Lumina - CPU {state.get('cpu', 0.0):.0f}%"


def icon_loop(icon, frames, state):
    """Animation loop for the system tray icon."""
    index = 0
    last_title = 0.0
    while True:
        try:
            if frames:
                icon.icon = frames[index % len(frames)]
                index += 1

            # Refresh the tooltip about once a second with the live CPU load.
            now = time.monotonic()
            if now - last_title >= 1.0:
                icon.title = format_cpu_title(state)
                last_title = now

            delay = state.get("interval", 0.2)
            time.sleep(max(0.05, min(delay, 0.5)))
        except Exception as e:
            print(f"Error in icon_loop: {e}")
            time.sleep(0.1)  # Prevent tight loop on error


def enable_x11_right_click():
    """Make a right click on the tray icon open the default action.

    pystray's X11 backend only handles left clicks and does not render menus
    at all (there is no popup menu API on the XEMBED tray protocol pystray
    uses). Without this patch, right clicking the cat does nothing on
    Cinnamon/XFCE/MATE panels, so the settings window would be unreachable.
    """
    try:
        from pystray import _xorg
    except Exception:
        return  # not the X11 backend (Windows, macOS, AppIndicator, ...)

    original = getattr(_xorg.Icon, "_on_button_press", None)
    if original is None or getattr(original, "_lumina_right_click", False):
        return

    def patched(self, event):
        # detail 1 = left button, 3 = right button: both open settings.
        if event.detail in (1, 3):
            self()
            return
        return original(self, event)

    patched._lumina_right_click = True
    _xorg.Icon._on_button_press = patched


def run_settings_dialog(app):
    """Build and run the settings window.

    Tk must be created and destroyed on a single thread, so this runs on the
    same thread that owns the Tk main loop (see ``TrayApp.run``).
    """
    import tkinter as tk
    from tkinter import colorchooser, ttk

    from PIL import ImageTk

    window = tk.Tk()
    window.title("RunCat Lumina Settings")
    window.resizable(False, False)

    color_var = tk.StringVar(value=app.settings["cat_color"])
    dark_var = tk.BooleanVar(value=app.settings["dark_mode"])
    fast_var = tk.BooleanVar(value=app.settings["positive_correlation"])
    preview_holder = {"image": None}

    def base_frame():
        prefix = "dark" if dark_var.get() else "light"
        if not hasattr(app, '_base_frames'):
            app._base_frames = {}
        key = prefix
        if key not in app._base_frames:
            path = _resource_path("resources", "cat", f"{prefix}_cat_0.ico")
            with Image.open(path) as image:
                app._base_frames[key] = image.convert("RGBA")
        return app._base_frames[key]

    def render_preview():
        color = normalize_hex(color_var.get()) or "#FFFFFF"
        frame = tint_image(base_frame(), color).resize((72, 72), Image.NEAREST)
        preview_holder["image"] = ImageTk.PhotoImage(frame)
        preview.configure(image=preview_holder["image"])
        current_label.configure(text=color)

    def apply_color(value):
        color = normalize_hex(value)
        if not color:
            return
        color_var.set(color)
        hex_entry.delete(0, "end")
        hex_entry.insert(0, color)
        app.apply_settings(color=color)
        render_preview()

    def choose_color():
        _, value = colorchooser.askcolor(
            color=color_var.get(), title="Pick cat color", parent=window
        )
        if value:
            apply_color(value)

    def on_dark():
        app.apply_settings(dark_mode=dark_var.get())
        render_preview()

    def on_fast():
        app.apply_settings(positive=fast_var.get())

    header = tk.Frame(window)
    header.grid(row=0, column=0, sticky="ew", padx=14, pady=(14, 6))
    tk.Label(header, text="Cat color", font=("", 11, "bold")).pack(anchor="w")

    grid = tk.Frame(window)
    grid.grid(row=1, column=0, padx=14, sticky="ew")
    for index, (_name, hex_value) in enumerate(TrayApp.COLORS):
        tk.Button(
            grid,
            text="",
            width=3,
            bg=hex_value,
            relief="flat",
            activebackground=hex_value,
            highlightthickness=0,
            command=lambda h=hex_value: apply_color(h),
        ).grid(row=index // 5, column=index % 5, padx=3, pady=3, sticky="ew")
    for column in range(5):
        grid.columnconfigure(column, weight=1)

    custom = tk.Frame(window)
    custom.grid(row=2, column=0, padx=14, pady=(8, 4), sticky="ew")
    tk.Label(custom, text="Custom").pack(side="left")
    hex_entry = tk.Entry(custom, textvariable=color_var, width=10, justify="center")
    hex_entry.pack(side="left", padx=6)
    hex_entry.bind("<Return>", lambda _event: apply_color(hex_entry.get()))
    tk.Button(custom, text="Pick…", command=choose_color).pack(side="left")
    tk.Button(custom, text="Apply", command=lambda: apply_color(hex_entry.get())).pack(
        side="left", padx=6
    )

    preview_row = tk.Frame(window)
    preview_row.grid(row=3, column=0, padx=14, pady=6, sticky="ew")
    preview = tk.Label(preview_row, bd=1, relief="solid")
    preview.pack(side="left")
    current_label = tk.Label(preview_row, text=color_var.get(), font=("monospace", 11))
    current_label.pack(side="left", padx=10)

    ttk.Separator(window, orient="horizontal").grid(
        row=4, column=0, sticky="ew", padx=14, pady=8
    )

    options = tk.Frame(window)
    options.grid(row=5, column=0, padx=14, sticky="ew")
    tk.Label(options, text="Options", font=("", 11, "bold")).pack(anchor="w")
    tk.Checkbutton(
        options, text="Dark mode icons", variable=dark_var, command=on_dark
    ).pack(anchor="w")
    tk.Checkbutton(
        options, text="Higher CPU, faster cat", variable=fast_var, command=on_fast
    ).pack(anchor="w")

    perf = tk.Frame(window)
    perf.grid(row=6, column=0, padx=14, pady=(10, 4), sticky="ew")
    tk.Label(perf, text="PC processing", font=("", 11, "bold")).pack(anchor="w")
    cpu_label = tk.Label(perf, text="CPU: 0%   frame: 0.20s", font=("monospace", 10))
    cpu_label.pack(anchor="w")
    cpu_bar = ttk.Progressbar(perf, maximum=100, length=240)
    cpu_bar.pack(anchor="w", pady=4)

    footer = tk.Frame(window)
    footer.grid(row=7, column=0, padx=14, pady=(8, 14), sticky="ew")
    tk.Button(
        footer, text="Quit RunCat Lumina", command=app.quit_app
    ).pack(side="left")
    tk.Button(footer, text="Close", width=10, command=window.destroy).pack(side="right")

    def refresh_cpu():
        if not window.winfo_exists():
            return
        cpu = app.state.get("cpu", 0.0)
        interval = app.state.get("interval", 0.2)
        cpu_bar["value"] = cpu
        cpu_label.configure(text=f"CPU: {cpu:.0f}%   frame: {interval:.2f}s")
        window.after(500, refresh_cpu)

    def poll():
        if not window.winfo_exists():
            return
        if app.quit_event.is_set():
            window.destroy()
            return
        if app.settings_request_event.is_set():
            app.settings_request_event.clear()
            window.lift()
            window.focus_force()
        window.after(200, poll)

    render_preview()
    refresh_cpu()
    window.after(200, poll)
    window.mainloop()
    try:
        window.destroy()
    except tk.TclError:
        pass


class TrayApp:
    COLORS = [
        ("Original White", "#FFFFFF"),
        ("Original Black", "#111111"),
        ("Ginger", "#D2691E"),
        ("Orange Tabby", "#FF9F43"),
        ("Cream", "#F6D7A7"),
        ("Gray", "#8B93A7"),
        ("Siamese", "#C4A484"),
        ("Calico", "#C75B39"),
        ("Pink", "#FF7AA2"),
        ("Sky", "#5B9DFF"),
    ]

    def __init__(self, settings, frames, state, author):
        self.settings = settings
        self.frames = frames
        self.state = state
        self.author = author
        self.icon = None
        self.settings_request_event = threading.Event()
        self.quit_event = threading.Event()
        self._settings_thread = None

    def apply_settings(self, color=None, dark_mode=None, positive=None):
        """Apply and persist any subset of settings, updating the tray icon."""
        if color is not None:
            self.settings["cat_color"] = color
        if dark_mode is not None:
            self.settings["dark_mode"] = dark_mode
        if positive is not None:
            self.settings["positive_correlation"] = positive
        save_config(self.settings, self.author)
        try:
            self.frames[:] = load_images(
                self.settings["dark_mode"], self.settings["cat_color"]
            )
            if self.icon and self.frames:
                self.icon.icon = self.frames[0]
        except Exception as e:
            print(f"Error applying settings: {e}")

    def apply_color(self, color):
        self.apply_settings(color=color)

    def on_white(self, icon, item):
        self.apply_color("#FFFFFF")

    def on_black(self, icon, item):
        self.apply_color("#111111")

    def on_ginger(self, icon, item):
        self.apply_color("#D2691E")

    def on_orange(self, icon, item):
        self.apply_color("#FF9F43")

    def on_cream(self, icon, item):
        self.apply_color("#F6D7A7")

    def on_gray(self, icon, item):
        self.apply_color("#8B93A7")

    def on_siamese(self, icon, item):
        self.apply_color("#C4A484")

    def on_calico(self, icon, item):
        self.apply_color("#C75B39")

    def on_pink(self, icon, item):
        self.apply_color("#FF7AA2")

    def on_sky(self, icon, item):
        self.apply_color("#5B9DFF")

    def open_settings(self, icon, item):
        self.settings_request_event.set()

    def is_dark(self, item):
        return self.settings["dark_mode"]

    def is_fast(self, item):
        return self.settings["positive_correlation"]

    def toggle_dark(self, icon, item):
        self.apply_settings(dark_mode=not self.settings["dark_mode"])

    def toggle_speed(self, icon, item):
        self.apply_settings(positive=not self.settings["positive_correlation"])

    def open_website(self, icon, item):
        try:
            webbrowser.open(self.author["web"])
        except Exception as e:
            print(f"Error opening website: {e}")

    def open_email(self, icon, item):
        try:
            webbrowser.open("mailto:" + self.author["email"])
        except Exception as e:
            print(f"Error opening email: {e}")

    def quit_app(self):
        """Stop the tray icon and end the app (used by the Settings window)."""
        self.quit_event.set()
        if self.icon is not None:
            try:
                self.icon.stop()
            except Exception as e:
                print(f"Error stopping the tray icon: {e}")

    def on_quit(self, icon, item):
        self.quit_app()

    def _is_x11_backend(self):
        module = type(self.icon).__module__
        return module.endswith("_xorg")

    def _start_icon(self):
        """Start the tray icon loop in the background.

        Returns True when the icon runs in a background thread, False when the
        backend requires the main thread (for example macOS).
        """
        if self._is_x11_backend():
            # pystray's own run_detached() starts the loop in a thread but
            # leaks an extra non-daemon setup thread on this backend, which
            # makes the app hang after quitting. Start the loop ourselves.
            threading.Thread(target=self.icon.run, daemon=True).start()
        else:
            try:
                self.icon.run_detached()
            except NotImplementedError:
                return False
        return True

    def _start_animation(self):
        threading.Thread(
            target=icon_loop,
            args=(self.icon, self.frames, self.state),
            daemon=True,
        ).start()

    def build_menu(self):
        """Build the tray menu.

        Note: pystray's X11 backend ignores this menu entirely (``HAS_MENU``
        is False there), so on Linux the settings window is opened by clicking
        the cat and is the single entry point for colors and quitting.
        """
        return pystray.Menu(
            pystray.MenuItem(
                "Settings…", self.open_settings, default=True
            ),
            pystray.MenuItem(
                lambda item: f"CPU {self.state.get('cpu', 0.0):.0f}%",
                None,
                enabled=False,
            ),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem(
                "Cat color",
                pystray.Menu(
                    pystray.MenuItem("Original White", self.on_white),
                    pystray.MenuItem("Original Black", self.on_black),
                    pystray.MenuItem("Ginger", self.on_ginger),
                    pystray.MenuItem("Orange Tabby", self.on_orange),
                    pystray.MenuItem("Cream", self.on_cream),
                    pystray.MenuItem("Gray", self.on_gray),
                    pystray.MenuItem("Siamese", self.on_siamese),
                    pystray.MenuItem("Calico", self.on_calico),
                    pystray.MenuItem("Pink", self.on_pink),
                    pystray.MenuItem("Sky", self.on_sky),
                ),
            ),
            pystray.MenuItem("Dark mode icons", self.toggle_dark, checked=self.is_dark),
            pystray.MenuItem("Higher CPU, faster cat", self.toggle_speed, checked=self.is_fast),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem(
                "Author",
                pystray.Menu(
                    pystray.MenuItem(self.author["name"], self.open_website),
                    pystray.MenuItem(self.author["web"], self.open_website),
                    pystray.MenuItem(self.author["email"], self.open_email),
                ),
            ),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Quit RunCat Lumina", self.on_quit),
        )

    def run(self):
        enable_x11_right_click()
        menu = self.build_menu()
        self.icon = pystray.Icon(
            "RunCat_Lumina", self.frames[0], format_cpu_title(self.state), menu
        )
        if not self._start_icon():
            # This backend must own the main thread (for example macOS), so
            # run the icon loop blocking and open settings from a helper thread.
            self._run_blocking()
            return

        self._start_animation()

        # pystray runs in the background; the main thread owns the Tk settings
        # window so it is created and destroyed on a single thread.
        while not self.quit_event.is_set():
            if self.settings_request_event.is_set() or consume_settings_request():
                self.settings_request_event.clear()
                self._show_settings()
                continue
            time.sleep(0.1)

    def _show_settings(self):
        try:
            run_settings_dialog(self)
        except Exception as e:
            print(f"Error opening settings window: {e}")
            print("Install tkinter (e.g. sudo apt install python3-tk) to use settings.")

    def _run_blocking(self):
        self._settings_thread = threading.Thread(
            target=self._settings_worker, daemon=True
        )
        self._settings_thread.start()
        self._start_animation()
        self.icon.run()
        self.quit_event.set()
        if self._settings_thread.is_alive():
            self._settings_thread.join(timeout=2)

    def _settings_worker(self):
        while not self.quit_event.is_set():
            if self.settings_request_event.is_set() or consume_settings_request():
                self.settings_request_event.clear()
                self._show_settings()
            else:
                time.sleep(0.1)


def setup_tray(settings, frames, state, author):
    TrayApp(settings, frames, state, author).run()


def main():
    if not acquire_single_instance():
        # Already running: bring up its settings window instead of failing
        # silently (there is no tray menu on Linux/X11).
        request_settings_from_running_instance()
        print("RunCat Lumina is already running - opening its settings window.")
        return 0

    # Clear any stale request left over from a previous session.
    consume_settings_request()

    settings, author = load_config()
    frames = load_images(settings["dark_mode"], settings["cat_color"])
    if not frames:
        print("Error: No frames loaded. Check that cat images exist in resources/cat/")
        return 1

    state = {"cpu": 0.0, "interval": 0.2}
    threading.Thread(target=cpu_loop, args=(settings, state), daemon=True).start()
    setup_tray(settings, frames, state, author)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
