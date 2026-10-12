#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$HOME/RunCatLumina"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
APP_MENU="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"

echo "RunCat Lumina Linux installer"
echo "Install folder: $APP_DIR"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Install Python first:"
  echo "  sudo apt install python3 python3-venv python3-pip"
  exit 1
fi
if ! python3 -c 'import venv' >/dev/null 2>&1; then
  echo "Install venv first:"
  echo "  sudo apt install python3-venv"
  exit 1
fi

mkdir -p "$APP_DIR/resources/cat" "$BIN_DIR" "$APP_MENU" "$ICON_DIR"

write_file() {
  cat > "$1"
}

write_b64() {
  base64 -d > "$1"
}

write_file "$APP_DIR/main.py" << 'FILE'
#!/usr/bin/env python3
import atexit
import json
import os
import tempfile
import threading
import time
import webbrowser
from pathlib import Path

import psutil
import pystray
from PIL import Image

ROOT = Path(__file__).resolve().parent
CONFIG_PATH = ROOT / "config.json"
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
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as file:
                data = json.load(file)
                settings.update(data.get("settings", {}))
                author.update(data.get("author", {}))
        except (json.JSONDecodeError, IOError) as e:
            print(f"Warning: Could not load config: {e}. Using defaults.")

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
        pixels = tinted.load()
        red, green, blue = hex_to_rgb(color)
        # Normalize color to 0-1 range
        red_norm, green_norm, blue_norm = red / 255.0, green / 255.0, blue / 255.0

        width, height = tinted.size
        for y in range(height):
            for x in range(width):
                pixel = pixels[x, y]
                if pixel[3] == 0:  # Transparent pixel
                    continue
                # Tint by multiplying with color, preserving original brightness
                r, g, b, a = pixel
                # Apply tint while preserving some original character
                pixels[x, y] = (
                    int(r * red_norm),
                    int(g * green_norm),
                    int(b * blue_norm),
                    a
                )
        return tinted
    except Exception as e:
        print(f"Error tinting image: {e}")
        return image  # Return original if tinting fails


def load_images(dark_mode, color):
    prefix = "dark" if dark_mode else "light"
    frames = []
    for index in range(5):
        try:
            path = ROOT / "resources" / "cat" / f"{prefix}_cat_{index}.ico"
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
    while True:
        try:
            cpu_usage = psutil.cpu_percent(interval=1)
            state["cpu"] = cpu_usage
            state["interval"] = cpu_to_interval(
                cpu_usage, settings["positive_correlation"]
            )
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
            time.sleep(max(0.02, delay))
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
        path = ROOT / "resources" / "cat" / f"{prefix}_cat_0.ico"
        with Image.open(path) as image:
            return image.convert("RGBA")

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
FILE

write_file "$APP_DIR/config.json" << 'FILE'
{
    "author": {
        "name": "AL ASAR JADEED",
        "web": "https://alasarjadeed.com",
        "email": "info@alasarjadeed.com"
    },
    "settings": {
        "dark_mode": true,
        "positive_correlation": true,
        "cat_color": "#FFFFFF"
    }
}
FILE

write_file "$APP_DIR/requirements.txt" << 'FILE'
Pillow
psutil
pystray
FILE

write_file "$APP_DIR/VERSION" << 'FILE'
1.0.0
FILE

write_file "$APP_DIR/LICENSE" << 'FILE'
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but not
      limited to compiled object code, generated documentation, and
      conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms of this License,
      without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS
FILE

write_b64 "$APP_DIR/resources/cat/dark_cat_0.ico" << 'B64'
AAABAAIAEBAAAAEAIABoBAAAJgAAACAgAAABACAAqBAAAI4EAAAoAAAAEAAAACAAAAABACAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB///
/mf///48AAAAB////CQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB//
//J/////////+d////wf///wX///9V////PwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAf///13//////////////+0AAAAB////tf////////8FAAAAAQAAAAEAAAAB////m////7H///9v
AAAAAQAAAAH///9d////////////////////4f///+f/////////OQAAAAEAAAABAAAAAf///3n///+
R////yf///9H///9z////xf///////////////////////////////////4MAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAH///9J////mf///7P////n////////////////////////////////////z////ycAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////Bf///1v///9T////gf/////////F////nf////3/
//9nAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///+z////z////8P
///+P////DQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////L////9
f////9////ewAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///
wX///8l////Qf///z8AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoAAAAIAAAAEAAAAABACAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAf///2v////X////KwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAH///9Z//////////////8VAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAAB////B///////////////OwAAAAH///+n////y////wUAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///97/////////9H///8N////yf/////////
p////AwAAAAH///9v////2f///10AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///9H/////////4/////P//
////////////08AAAABAAAAAf///2X//////////////z0AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////q//////
/////////////////////////fQAAAAEAAAAB////D/////3/////////wQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAf///w////8JAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AH///+5////////////////////////////////////s////3////+/////////////////////NQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH////B///////////////f////if///ykAAAABAAAAAQA
AAAEAAAAB////G/////n///////////////////////////////////////////////////////////
////////9tAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///9/////3////3////////////////
////63///8xAAAAAQAAAAH///8b////////////////////////////////////////////////////
/////////////////////30AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///wUAAAAB///
/A////0H///+5//////////////+5////b////4X///////////////////////////////////////
//////////////////////////////////2////xsAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAH///9D////vf//////////////////////////////////////////
////////////////////////////////////////////////////9f///5H///8DAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////Hf///1H///9x////bf///8n///
///////////////////////////////////////////////////////////////////////////9H//
/8HAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAf///1////+v////0////8P///+Z////x//////////////////////////v////5//////
//////////////4sAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////q////////////////////
zkAAAAB/////////0H///+X////0QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///8R////8//
/////////////cf///0X/////////Jf///2n///9pAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAH///+t////vf///5//////////////////////////awAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAf///z3////T////Uf////P/////////zf///78AAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///4P/////////d////4f////l////lQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///7P///9RAAAAAf///+n///
+hAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
B64

write_b64 "$APP_DIR/resources/cat/dark_cat_1.ico" << 'B64'
AAABAAIAEBAAAAEAIABoBAAAJgAAACAgAAABACAAqBAAAI4EAAAoAAAAEAAAACAAAAABACAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////G////0P///83//
//5f///yUAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///xv////3/
///2f/////////z////RQAAAAEAAAABAAAAAQAAAAEAAAAB////E////yMAAAABAAAAAQAAAAEAAAAB
////Jf////X////////////////////b////w////5H///8v////Y////+//////////Pf///0////9
j////GwAAAAEAAAAB////qf//////////////////////////////////////////////f////xf///
9f////tf///7/////J////t////7f////j/////////////////////////////////////////1sAA
AABAAAAAQAAAAH///8b////R////1X///8v////A////23///+n////sf///9X/////////8f///9X/
////////cQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////2////+f
///+n////0f///0MAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///z
v////x/////////7sAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAAB////Zf///3v///9fAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoAAAAIAAAAEAAAAABACAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAf///9X/////////KQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAH///8F////GQAAAAEAAAAB////sf/////////n////DwAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAf///2X/////////t////yf///8n////9//////////Z////IQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////J/////v//////////////5n////r///////////
////5////XQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
H///8LAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////K/////f//////////////
///////////////////////////lf///2v///9t////Q////xsAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAH///87////0f///+X///8jAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////N//
///P/////////////////////////////////////////////////////////+////8f///99////EQ
AAAAH///9J////uf////////////////////////9/AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAAB////Gf///4X/////////////////////////////////////////////////////////
///////////p////vf///////////////////////////////////00AAAAB////A////yP///8TAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///yn////l//////////////////////////////////
///////////////////////////////////////////////////////83///8tAAAAAQAAAAH///9v/
//////////////R////l////2////9V////Of///zn///81////J////9X/////////////////////
//////////////////////////////////////////////////////////////+jAAAAAQAAAAEAAAA
BAAAAAf///yH///9h////s/////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////9H//
/+R////JwAAAAEAAAABAAAAAQAAAAEAAAAB////B////0X///99////o////6v///+3////uf///6v/
//+H////T////3/////////////////////////////////////////////////////////////////
////////////////////9////MwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAf///yX///+D////uf///8/////F////0f////3//////////////
//////////////////////////////////////pAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////H//
//4f///////////////////+5////Gf///+X////D////Yf////8AAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAf///7///////////////7cAAAAB////6f///5H///8N////qQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAAB////Pf///9////+b//////////n//////////////7v///8dAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////0////2X///+f/////////9H////j
////RwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///8//////////73///
+J////y////7f///89AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH/
//9/////0QAAAAH///+p/////////xsAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
B64

write_b64 "$APP_DIR/resources/cat/dark_cat_2.ico" << 'B64'
AAABAAIAEBAAAAEAIABoBAAAJgAAACAgAAABACAAqBAAAI4EAAAoAAAAEAAAACAAAAABACAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///8zA
AAAAf///7f////D////EQAAAAEAAAABAAAAAQAAAAH///8Z////p////9v///8fAAAAAQAAAAEAAAAB
////vf////v////h/////////+n///+L////jf///5n///+b////8f//////////////hQAAAAEAAAA
BAAAAAf///xn////V////////////////////////////////////////////////////4f///0kAAA
ABAAAAAQAAAAEAAAABAAAAAf///yf////d////////////////////////////////////7////8n//
/9/AAAAAQAAAAEAAAABAAAAAQAAAAH///9J////6////83////7////5f///43///+z/////////7P/
//+T////iwAAAAH///9t////xf///7P////L////4////10AAAAB////G////wUAAAABAAAAAf///7f
////1/////////3UAAAAB////H////3X///+R////aQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
H///8n////i////5H///9XAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoAAAAIAAAAEAAAAABACAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB//////////////+vAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///wn///+H////8///////
//9zAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///w////87AAAAAQAAAAH///9x///////////
////F////JQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///9Z////4f////
//////////rQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////mf/////////T////gf///
2v////3///////////////7////bf///w0AAAAB////Df///x3///8Z////Hf///xH///8p////p///
//////////////////////+T////Yf///zcAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///9x///////
/////////////////////////////////////////////7f///83////t/////f////n////9////8f
//////////////////////////////////////////////hQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAH///9v////////////////////////////////////////////////////////////////////
///////////////////////////////////////////5////vf///2MAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAH///9V////9/////////////////////////////////////////////
///////////////////////////////////////////////////////9////8vAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///8f////d////9H/////////////////////
///////////////////////////////////////////////////////////////////////////////
f////GwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///6X///
///////////////////////////////////////////////////////////////////////////////
//////////////////BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAAB////j//////////////////////////////////////////////////////////////////////
////P////Hf///9f///+fAAAAAf///8UAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAAB////If///73//////////////7X////r////////////////////0////2n///8f////T////
////////////////80AAAAB////u////9H///9j////ZwAAAAEAAAAB////Sf///4P///9N////J///
/w3///8d////P////43//////////////+3///87AAAAAf///w////9R////Yf///y8AAAABAAAAAQA
AAAEAAAAB////S//////////D//////////f//////////////8////8DAAAAAQAAAAH///+D//////
////////////////////////////////////3///+D////EQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAAB////v////5X///9l//////////f////B////cQAAAAEAAAABAAAA
AQAAAAH///81////g////7P////X////0////6X///9l////EQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///8b////3f///8////91////j/////H///+lAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///8V////9f///2EAAAAB
////wf///4kAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
B64

write_b64 "$APP_DIR/resources/cat/dark_cat_3.ico" << 'B64'
AAABAAIAEBAAAAEAIABoBAAAJgAAACAgAAABACAAqBAAAI4EAAAoAAAAEAAAACAAAAABACAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB///
/Jf///xUAAAABAAAAAQAAAAH///8F////0f///2UAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAf///+3///9hAAAAAQAAAAEAAAAB////jf////////+5////q////wUAAAABAAAAAQAAAAEAAAABA
AAAAf///zP/////////YwAAAAH///9T////gf///////////////////18AAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAH///+f/////////+3////h//////////////////////////v///+h////RwAAAAEAAAA
BAAAAAQAAAAEAAAAB////hf/////////////////////////////////////////P////2f///40AAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAH////L////////////////////gf///6n/////////sf///8v//
/9TAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////x////8P///+t////SwAAAAEAAAAB////lf//////
////////kQAAAAEAAAAB////I////zP///9h////1f///50AAAABAAAAAQAAAAEAAAABAAAAAQAAAAH
///9n////Mf///z0AAAABAAAAAf///5n////T////x////3UAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoAAAAIAAAAEAAAAABACAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////N
f///+/////r////CwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAH///8Z////PQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAf///xn////x/////////7MAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///6v/////////NwAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAAB////1f/////////5////If///xv///8rAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////1f////////9pAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAf///3v///////////////n////h///////////////JAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///xf//////////////zMAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAH///8L////8f//////////////////////////////7////4EA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////of/////
/////////fwAAAAEAAAAB////Gf///1P///+J////t////+X//////////////////////////////4
cAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///
w3/////////////////////////wf///6n////5////////////////////////////////////////
////////////lf///1X///8jAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAAB////Kf////////////////////////////////////////////////////////////////
////////////////////////////////////////91AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAH///9l////////////////////////////////////////////////////
//////////////////////////////////////////////////////////9DAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///xf////d//////////////////////////////////
////////////////////////////////////////////+9////i/////////8j////Yf///6UAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///03/////////////////////
///////////////////////////////l/////////////////////////1sAAAAB////9////3n///9
x////UQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///73///
//////////////////////////////////////af///wX///9L/////////////////////f///7n//
//9/////////6EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAAB////Q///////////////////////////////4f///zsAAAABAAAAAQAAAAH///9T/////////5/
///+z//////////////+5////gf///wUAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAH///+//////////3H///+H////q////2v///8JAAAAAQAAAAEAAAABAAAAAQAAA
AH///9v////2f///23///+f////pf///9/////t////OQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAAB////o/////////93AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAH///9p/////////+MAAAAB////ff///7P///8fAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAH///8l////a////+//////////iQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///8d////ef///wUAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAAB////of///+3////h////7///////////////8////2EAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAH///+V////9f//////////////u////10AAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
B64

write_b64 "$APP_DIR/resources/cat/dark_cat_4.ico" << 'B64'
AAABAAIAEBAAAAEAIABoBAAAJgAAACAgAAABACAAqBAAAI4EAAAoAAAAEAAAACAAAAABACAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAf///33///+dAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAH///8t////z////43/////////iQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAH///9b/////////////////////////0cAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAAB////y/////////////////////////+7////GwAAAAEAAAABAAAAAf///yf///+
b////t////4n///8j////U//////////////////////////////////////////T////MQAAAAH///
+H////1f///5/////H////7////////////////////////////////////+X///+/////6////1cAA
AABAAAAAQAAAAEAAAABAAAAAf///yf///+V////0//////////z////m////9f////V////r////9n/
//8XAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///8v////EwAAAAH///8Z////3f/////
////b////IwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///0
P///87////L////xsAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoAAAAIAAAAEAAAAABACAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////V////5H///8TAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///zX////////
//////x0AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///+B////nf///yEAAAAB/
///wf////////+/AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///8R////Yf/////////
/////5////2H////z/////////5EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///8V////u/////H//
///////////////////////////////////////mwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///y3
///////////////////////////////////////////////////+1AAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAAB////J////////////////////////////////////////////////////98AAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAf///xP////V//////////////////////////////////////////////////////
///4n///8dAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAf///xf///8l////G
QAAAAEAAAABAAAAAQAAAAEAAAAB////n///////////////////////////////////////////////
//////////////////////3////b////of///ycAAAABAAAAAQAAAAEAAAABAAAAAf///y3///+1///
/////////////////0f///3H///8vAAAAAQAAAAH////3//////////////////////////////////
///////////////////////////////////////////////////////yUAAAABAAAAAQAAAAH///9f/
///////////////////4/////f///////////////////+7////if////3/////////////////////
/////////////////////////////////////////////////////////+X////v////rwAAAAEAAAA
BAAAAAf///1X////X////i////xkAAAAB////Cf///z3///+j//////////////////////////////
//////////////////////////////////////////////////////x////0P////x////hQAAAAH//
/+7AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///8t////lf////H/
//////////////////////////////////////////////////////////////////+pAAAAAf///83
////Z////k////2EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAAB////Ef///2H///+5/////f///////////////////83///9p////Pf///6P/////////3////
//////l/////f/////////VAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAH///8d////U////2v///9DAAAAAQAAAAEAAAABAAAAAf/
//9n///+V////c///////////////v////3cAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAAB////K////9////+v////if///5H////v////wQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAAB////J/////////+XAAAAAf///7P///+lAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB////E////zUAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
B64

write_b64 "$APP_DIR/resources/cat/light_cat_0.ico" << 'B64'
AAABAAIAEBAAAAEAIABoBAAAJgAAACAgAAABACAAqBAAAI4EAAAoAAAAEAAAACAAAAABACAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAADAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAABAAAA
AQAAAAUAAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAABAAA
ATwAAAGUAAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAADAAAAAQAAAAEAAAABAA
AAFwAAAOUAAABxAAAAgQAAAA8AAAApAAAABwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAJA
AAAAQAAAF0AAAD7AAAA6wAAAM8AAAABAAAAtwAAAJ8AAAABAAAAAwAAAAEAAAABAAAAPwAAAE0AAAAP
AAAAAQAAAAEAAABhAAAA/wAAAP8AAADpAAAAhwAAANUAAAD/AAAAGQAAAAEAAAADAAAAAQAAAJ0AAAC
1AAAAxQAAAI0AAAAPAAAAmwAAAP8AAAD1AAAA/wAAAP8AAAD/AAAA/wAAAEEAAAABAAAABQAAAAEAAA
ABAAAAAQAAABUAAACLAAAAvwAAANcAAAD/AAAA/wAAAP8AAAD/AAAA+QAAAP8AAADrAAAAWQAAAAEAA
AADAAAAAwAAAAUAAAABAAAAAQAAAAUAAAANAAAATwAAAKkAAACXAAAAywAAAP8AAADbAAAA2wAAAPEA
AAA3AAAAAQAAAAEAAAABAAAAAQAAAAUAAAABAAAAAQAAAAEAAAABAAAAAQAAABkAAAD1AAAAuwAAAKs
AAACLAAAAJwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAABQAAAAcAAAABAAAAbQAAAN
UAAAD7AAAAaQAAAAEAAAAFAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
BsAAABZAAAAYwAAADsAAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAMAAAADAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoAAAAIAAAAEAAAAABACAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
MAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAMAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAADAAAAAQAAABcAAABZAAAADQAAAAEAAAADAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAwAAAAEAAAATAAAAxwAAAP8AAAA5AAAAAQAAAAEAAAABAAAAAQAAAAMAAAAFAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAALEAAAD/AAAApwAAAAEAAAA3AAAATwAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAEAAAA9AAAA/wAAAPMAAAAhAAAAZwAAAP8AAAD
jAAAACwAAAAEAAAAvAAAAbwAAAA8AAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAQAAAKUAAAD/AAAA1QAAAJcAA
AD/AAAA/wAAAIsAAAABAAAAAQAAAIkAAAD/AAAAuwAAAA8AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAMAAAADAAAAAwAAAAMAAAADAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAtQAAAP8
AAAD/AAAA/wAAAP0AAAD/AAAAUwAAAAEAAAABAAAANQAAAPkAAAD/AAAAdQAAAAEAAAAFAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAwAAAAEAAAABAAAAAwAAA
AEAAACjAAAA/wAAAPsAAAD9AAAA/QAAAP8AAADLAAAAQQAAABMAAABvAAAA/wAAAP8AAADVAAAADwAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAzAAAAfQAAAHcAAABTAAAAHwAAAAEAAAABAAAAAQA
AAAMAAAABAAAACQAAAM0AAAD/AAAA/QAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA5wAAAP8AAAD/AAAA/Q
AAAP8AAABRAAAAAQAAAAMAAAABAAAAAQAAAAEAAAABAAAAAQAAAN0AAAD/AAAA/wAAAP8AAAD7AAAAp
wAAADcAAAABAAAAAQAAAAEAAAAvAAAA+wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/QAAAP8AAAD/AAAA
/wAAAP8AAAD9AAAA/wAAAGMAAAABAAAABwAAAAEAAAABAAAAAQAAAAEAAAABAAAARwAAAGkAAABTAAA
AZwAAAK8AAAD/AAAA/wAAAKsAAAA5AAAAAwAAADkAAAD5AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AA
AA/wAAAP8AAAD/AAAA/wAAAP0AAAD/AAAAmQAAAAEAAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAADEAAACrAAAA/wAAAP8AAADjAAAA4QAAAP8AAAD/AAAA/QAAAP8AAAD/
AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD3AAAAhQAAAB8AAAABAAAAAwAAAAEAAAA
BAAAAAQAAAAMAAAADAAAAAwAAAAUAAAADAAAAAQAAAAEAAAA7AAAAiwAAAMUAAADfAAAA2QAAAP8AAA
D/AAAA/wAAAP0AAAD/AAAA/wAAAP0AAAD/AAAA/wAAAP8AAAD/AAAA/QAAAP8AAAD/AAAA7QAAAFMAA
AABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAQAAAAEAAAABAAAAAQAAABEA
AAALAAAAWQAAANMAAAD/AAAA/wAAAP8AAAD7AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAPs
AAAD/AAAA/wAAADUAAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAA
MAAAABAAAAAQAAAAEAAAABAAAABwAAAD8AAABbAAAATwAAAC8AAABZAAAA5wAAAP8AAAD7AAAA/wAAA
KUAAACXAAAA/wAAALkAAADrAAAAlwAAAAEAAAADAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAABjAAAA/wA
AAP8AAAD/AAAAQQAAACcAAAD/AAAADQAAAHUAAACBAAAAAQAAAAMAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAABQAAAAMAAAADAAAAA
QAAAAUAAADJAAAA4wAAAP8AAADVAAAAxwAAAP8AAAChAAAAiQAAABkAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAAFAAAAAQAAAHkAAAClAAAAawAAAP8AAAD/AAAA+wAAAOEAAAAhAAAAAQAAAAMAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAADwAAAMkAAACdAAAAtwAAAM8AAACbAAAAjwAAAAEAAAAD
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAABAAAALwAAAP8AAABdAAAAVQAAAP8AAA
CdAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAABAAAANwAAACUA
AAABAAAAaQAAAEMAAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
MAAAABAAAAAQAAAAMAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAMAAAABAAAAAQAAAAUAAAADAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
B64

write_b64 "$APP_DIR/resources/cat/light_cat_1.ico" << 'B64'
AAABAAIAEBAAAAEAIABoBAAAJgAAACAgAAABACAAqBAAAI4EAAAoAAAAEAAAACAAAAABACAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAMAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAABQAAAAEAAABJAA
AAlwAAAAEAAAABAAAABQAAAAUAAAADAAAAAQAAAAMAAAADAAAAAwAAAAEAAAADAAAAAQAAACEAAACvA
AAAawAAAP8AAACJAAAAAQAAAAEAAAABAAAAAQAAAAUAAAABAAAAAQAAAAEAAAABAAAAAQAAAAUAAAAB
AAAAlwAAAP8AAAD9AAAA/wAAALcAAABxAAAAWQAAACEAAAABAAAAEwAAAI8AAACJAAAACQAAAAEAAAA
BAAAAAQAAAAEAAABJAAAA3wAAAPsAAAD/AAAA/wAAAP8AAAD3AAAArQAAAOcAAAD/AAAA6QAAABsAAA
BjAAAAtwAAAI8AAAB3AAAAUwAAALUAAAD/AAAA/wAAAPsAAAD7AAAA/wAAAP8AAAD/AAAA3QAAABcAA
AABAAAACQAAADsAAACBAAAAowAAAK8AAACTAAAAcwAAANsAAAD/AAAA/wAAAP8AAAD7AAAA/wAAAP8A
AADdAAAAJQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAJAAAALwAAACsAAABvAAAA/wAAANs
AAACbAAAAzwAAAGMAAAABAAAAAwAAAAUAAAAFAAAABQAAAAUAAAAFAAAAAQAAAAEAAAABAAAAAQAAAJ
UAAADPAAAA3wAAAJkAAAAPAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAABQAAA
AEAAAAnAAAAqwAAAMMAAAB/AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAABsAAAAbAAAAKQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAADAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoAAAAIAAAAEAAAAABACAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAw
AAAAMAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAMAAAAFAAAAAQAAAHMAAACZAAAABQAAAAEAAAADAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAuQAAAP8AAACTAAAAAQAAAAMAAAADAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAADAAAAAQAAACsAAACXAAAAUQAAAAEAAABnAAAA/wAAAP8AAAB7AAAAAQAAAAEAA
AADAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAwAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAABAAAARQAAAP8AAAD/AAAAqQAAAFUAAADrAAAA/wAAAP8
AAACbAAAADwAAAAEAAAABAAAAAQAAAAEAAAADAAAAAwAAAAEAAAABAAAAAQAAAAEAAAADAAAAAQAAAA
EAAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAABAAAAdwAAAP8AAAD/AAAA9QAAA
PcAAAD/AAAA/QAAAP8AAADJAAAAKQAAAA8AAAAPAAAAAQAAAAEAAAABAAAAAQAAAAMAAAAFAAAAAQAA
AAEAAAABAAAAYwAAAGcAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAiwA
AAP8AAAD/AAAA/wAAAP8AAAD/AAAA+wAAAP8AAADzAAAA3wAAANsAAAC5AAAAkQAAAFMAAAAZAAAAAQ
AAAAEAAAAFAAAATwAAALcAAAD/AAAA+wAAAJMAAAArAAAAAQAAAAEAAAADAAAAAwAAAAMAAAADAAAAA
wAAAAEAAAABAAAAewAAAOcAAAD/AAAA/wAAAP8AAAD/AAAA/QAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA
/wAAAOkAAAB9AAAARwAAAMEAAAD/AAAA/wAAAPsAAAD/AAAA/wAAAGMAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAFwAAALMAAAD/AAAA/QAAAP8AAAD/AAAA/wAAAP0AAAD9AA
AA/QAAAP0AAAD9AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD7AAAA/wAAAP8AAACHAAAAAQAAAAEAAAAhA
AAAnQAAAIMAAABFAAAAJQAAAA0AAAABAAAAAQAAAAEAAAABAAAAAQAAAMkAAAD/AAAA+wAAAP8AAAD/
AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD9AAAA/QAAAP8AAAD9AAAA/wAAAP8AAADXAAAASwAAAAEAAAA
BAAAAAQAAADUAAADVAAAA/wAAAP8AAAD/AAAA4QAAAMsAAACzAAAAsQAAALMAAAC3AAAA8QAAAP8AAA
D/AAAA/QAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAJkAA
AAZAAAAAQAAAAEAAAABAAAAAQAAAAEAAAArAAAAbwAAALkAAADlAAAA/wAAAP8AAAD/AAAA/wAAAP8A
AADxAAAAxQAAAOUAAAD/AAAA/wAAAP8AAAD9AAAA/wAAAP0AAAD9AAAA/wAAAP8AAAD/AAAA/wAAAP8
AAAD7AAAA/wAAAPsAAAB/AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAABUAAAAvAAAAMwAAAD
sAAAA7AAAAMwAAACMAAAABAAAAGwAAAJcAAADtAAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAA
P8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAB3AAAAAQAAAAEAAAABAAAAAwAAAAMAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAB0AAABJAAAAWQAAAFMAAABdAAAAlQA
AAOsAAAD/AAAA/QAAAP8AAADnAAAArwAAAPsAAADrAAAA4wAAAN0AAAAFAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAwAAAAMAAAADAAAAAwAAAAMAAAADAAAAAQAAAAMAAAADAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAMQAAAPMAAAD/AAAA/wAAAKEAAAABAAAA2wAAAHsAAAAlAAAAxwAAAAMAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAwAAAAMAAAADAAAABQAAAAUAAAABAAAAhQAAAPcAAAD1AAAA5QAAAIkAAAD7AAAAtQAAAIEAAABdAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAEAAAAnAAAAzwAAAFkAAAD1AAAA/wAAAPkAAAD/
AAAAdwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAEAAACbAAAApQAAAKEAAA
DjAAAApwAAALMAAAAdAAAAAQAAAAMAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAcA
AADZAAAAyQAAACkAAADZAAAAzwAAACcAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAADAAAAAQAAACUAAABfAAAAAQAAAFUAAACXAAAABQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAADAAAAAQAAAAEAAAADAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAEAAAADAAAAAwAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
B64

write_b64 "$APP_DIR/resources/cat/light_cat_2.ico" << 'B64'
AAABAAIAEBAAAAEAIABoBAAAJgAAACAgAAABACAAqBAAAI4EAAAoAAAAEAAAACAAAAABACAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAUAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAFAA
AACQAAAAEAAAADAAAAAwAAAAMAAAADAAAABQAAAAEAAAABAAAAAQAAAAUAAAABAAAAAQAAAAEAAAABA
AAAAQAAAMEAAABzAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAbQAAAL0AAAAPAAAAAQAAAAMAAAAB
AAAAoQAAAKUAAADDAAAA/wAAAJ8AAAA1AAAARwAAAE0AAABLAAAAvQAAAP8AAADzAAAAWQAAAAEAAAA
DAAAAAQAAAEkAAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA0QAAAD8AAA
ABAAAAAwAAAAcAAAABAAAAIwAAAJMAAADxAAAA/QAAAPkAAAD7AAAA/wAAAP8AAAD3AAAA/wAAAOMAA
ABbAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA4wAAAP8AAAD/AAAA/wAAANUAAADvAAAA/wAAAKEA
AACzAAAAkwAAAAEAAABVAAAAdQAAAFEAAAB9AAAA5wAAAJEAAAAvAAAAbwAAAEsAAAABAAAAQQAAAOE
AAADBAAAA5QAAAEkAAAABAAAAPwAAAJ8AAACvAAAAmQAAADUAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAABjAAAAtwAAALkAAABDAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAMAAAAFAAAAAwAAA
AEAAAABAAAABwAAABsAAAARAAAAEwAAAAEAAAADAAAABQAAAAMAAAAFAAAAAwAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoAAAAIAAAAEAAAAABACAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAADAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAADAAAAAQAAAAMAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAMAAAAFAAAAsQAAAN0AAABLAAAAAQAAAAMAA
AADAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAQAAAAEAAAApAAAAjwAAALsA
AAA7AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAADJAAAA/wAAAPk
AAABfAAAAAQAAAAEAAAAFAAAAAwAAAAMAAAADAAAAAwAAAAMAAAADAAAAAwAAAAEAAAALAAAAgQAAAP
MAAAD/AAAA/QAAADkAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAABAAAAQQAAALcAAABtAAAAEQAAA
EsAAAD3AAAA/wAAAP8AAACZAAAAEQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAARwAA
ANUAAAD/AAAA/wAAAP8AAABpAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAABQAAAAEAAACFAAAA/wA
AAP8AAADrAAAA1wAAAPcAAAD/AAAA/wAAAP8AAADdAAAAfwAAAFcAAAB/AAAAkwAAAI0AAACVAAAAhQ
AAAKMAAAD9AAAA/wAAAPsAAAD/AAAA/wAAAOEAAADvAAAAXwAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAB0AAADJAAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/QAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA
/wAAAP8AAAD/AAAA/wAAAP8AAAD9AAAA/wAAAP8AAAD/AAAA/wAAANkAAAAvAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAADAAAAAQAAAA0AAAC1AAAA/wAAAP8AAAD9AAAA/wAAAP8AAAD/AAAA/QAAAP0AAAD9AA
AA/QAAAP0AAAD9AAAA/QAAAP0AAAD9AAAA/wAAAP8AAAD9AAAA/wAAAOEAAABPAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAQAAAAUAAACFAAAA5QAAAP8AAAD/AAAA/wAAAP8AAAD/
AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP0AAAD/AAAA4QAAAI8AAAB
LAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAQAAAAEAAAAPAAAAYQAAAO8AAA
D/AAAA/QAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/QAAAPsAAAD9AAAA/wAAAP8AAAD/AAAA/wAAAP8AA
AD/AAAA/wAAAP8AAABXAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAABQAAAAEA
AAABAAAAdwAAAP8AAAD9AAAA/QAAAP0AAAD9AAAA/QAAAP0AAAD/AAAA/wAAAP8AAAD9AAAA/wAAAP8
AAADvAAAAqwAAAPkAAAC5AAAAjQAAAL0AAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAADAAAAAwAAAA
MAAAABAAAAAQAAAEkAAADVAAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAANUAAACdAAAAywAAA
P8AAAD7AAAA/wAAALEAAAABAAAAwwAAAIEAAAARAAAAlQAAAAEAAAABAAAAAQAAAAcAAAABAAAAAQAA
AAEAAAABAAAAAQAAABUAAACFAAAA/wAAAP8AAACxAAAAQQAAAIUAAADDAAAAzwAAAKsAAABlAAAADwA
AAAEAAAAFAAAAuQAAAP8AAAD/AAAA7QAAAH0AAADrAAAA8wAAALMAAAAtAAAAAwAAAAEAAABRAAAA7w
AAAMEAAACdAAAAfQAAAIkAAACtAAAA7QAAAP8AAADxAAAAgQAAAAEAAAABAAAAAQAAAAEAAAAHAAAAA
QAAAAEAAAABAAAABQAAAAEAAAAZAAAA4wAAAHkAAADVAAAA/wAAAO8AAAD7AAAAdQAAAAEAAAADAAAA
AQAAACMAAACvAAAA9wAAAP8AAAD/AAAA/wAAAP8AAADfAAAAhQAAACEAAAABAAAAAQAAAAUAAAADAAA
AAQAAAAEAAAADAAAAAwAAAAEAAAABAAAABQAAAAEAAAB1AAAAtwAAAHUAAADRAAAAzQAAAJsAAAB3AA
AAAQAAAAEAAAABAAAAAQAAAAEAAAAVAAAANwAAAEsAAABNAAAANQAAAA0AAAABAAAAAQAAAAMAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAACLAAAA/wAAAFUAAABh
AAAA/wAAAIsAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAA
DAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
BfAAAAMQAAAAEAAABJAAAALwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAADAAAAAwAAAAMAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAwAAAAEAAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAABQAAAAMAAAABAAAAAwAAAAMAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
B64

write_b64 "$APP_DIR/resources/cat/light_cat_3.ico" << 'B64'
AAABAAIAEBAAAAEAIABoBAAAJgAAACAgAAABACAAqBAAAI4EAAAoAAAAEAAAACAAAAABACAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAMAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAMAAAABAAAAlwAAAEcAAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAKMAAAArAAAAAQAAAAEAAAABAAAAcwAAAP8AAAB1AAAASQAAAAEAAAABAAAAAQAAAAEAAAADA
AAAAQAAAB8AAAD/AAAALwAAAAEAAAARAAAAOwAAAPEAAAD/AAAA+QAAAHkAAAABAAAAAQAAAAEAAAAB
AAAABQAAAAEAAAB5AAAA/wAAAL8AAACrAAAA6wAAAP8AAAD9AAAA/wAAANcAAABTAAAACQAAAAEAAAA
BAAAAAQAAAAUAAAABAAAAmwAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAPsAAAD5AAAA9wAAAGUAAA
ABAAAAAQAAAAEAAAADAAAAAQAAADUAAAD5AAAA/wAAAP8AAAD/AAAAyQAAAO8AAAD/AAAAjwAAALEAA
ABNAAAAAQAAAAEAAAADAAAABQAAAAEAAAABAAAAvQAAAP0AAADzAAAAiQAAAAEAAABBAAAA0wAAANUA
AAD5AAAATwAAAAEAAAABAAAAAQAAAAEAAAABAAAAewAAAK8AAAATAAAAGQAAAAEAAAABAAAAAQAAADk
AAACXAAAAXQAAAEcAAAABAAAAAQAAAIUAAAC1AAAAwwAAAJ0AAAAJAAAAAQAAAAEAAAADAAAAAQAAAA
MAAAABAAAACQAAAAEAAAABAAAAAQAAAAEAAAAzAAAATwAAACMAAAABAAAAAQAAAAMAAAABAAAAAQAAA
AEAAAABAAAAAwAAAAEAAAADAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAADAAAAAwAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoAAAAIAAAAEAAAAABACAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAMAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAABAAAAD
QAAAIcAAABlAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAClAAAA/wAAANkAAAAHAAAAAQAAAAMAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAQAAAF8AAAC3AAAAFwAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAMAAAABAAAAhQAAAP8AAAD5AAAAOQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAtQAAAP8AAABXAAAAAQAAAAMAAAA
BAAAAAQAAAAMAAAAHAAAAAQAAAEsAAAD/AAAA/wAAAOsAAACJAAAAnQAAAKkAAABLAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAkAAADVAAAA/wAAAFcAA
AABAAAABwAAAAMAAAABAAAAAQAAAAEAAAABAAAAwwAAAP8AAAD7AAAA/wAAAP8AAAD/AAAA/wAAAKkA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAABAAAAVQAAAP8
AAAD/AAAASwAAAAEAAAABAAAAAQAAAAMAAAAjAAAAQwAAAIMAAAD9AAAA/wAAAP8AAAD/AAAA/wAAAN
kAAABfAAAADQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AkAAADPAAAA/wAAAP8AAADXAAAAXQAAAD8AAACPAAAAyQAAAPEAAAD/AAAA/wAAAP8AAAD/AAAA/wAA
AP8AAAD/AAAAYQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAGQAAAO0AAAD/AAAA/QAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD9AAAA/w
AAAP8AAAD/AAAA/wAAAP8AAADvAAAA2wAAAJEAAAARAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAwAAAAEAAABDAAAA/QAAAP8AAAD/AAAA/QAAAP8AAAD/AAAA/QAAAP0AAAD/AAAA
/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAALsAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAQAAAD8AAAD7AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AA
AA/wAAAP8AAAD9AAAA/QAAAP0AAAD/AAAA/wAAAP8AAAD5AAAA8QAAAP8AAACVAAAAvwAAAEsAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAQAAAIsAAAD/AAAA+wAAAP8AAAD/
AAAA/wAAAP8AAAD/AAAA/QAAAP8AAAD/AAAA/wAAAP0AAAD9AAAA/wAAAHkAAAAtAAAA9wAAACEAAAB
lAAAAVQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAABAAAAIQAAAPEAAA
D/AAAA/QAAAP8AAAD/AAAA/QAAAP0AAAD/AAAA0wAAAGkAAADDAAAA/wAAAPsAAAD/AAAAmQAAAE0AA
AD3AAAA5QAAAJUAAAAFAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMA
AAABAAAAdQAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAKUAAAAPAAAAAQAAAA0AAADFAAAA/wAAANc
AAAD/AAAA/wAAAPMAAAD7AAAAcQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAABwAAAAEAAABrAAAA/wAAAN0AAADtAAAA+wAAAN8AAABzAAAAAQAAAAEAAAAHAAAAAQAAA
AsAAADLAAAAiwAAAG8AAADtAAAA4wAAAJkAAACjAAAABQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAwAA
AAMAAAADAAAAAwAAAAEAAAABAAAALQAAAPsAAADVAAAAEwAAACUAAAA5AAAADwAAAAEAAAABAAAAAwA
AAAEAAAADAAAAAQAAAB8AAADJAAAAxwAAAKcAAABJAAAA2wAAANUAAAARAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAFEAAADzAAAA8QAAACcAAAABAAAAAQAAAAEAAAABAAAAA
wAAAAEAAAABAAAAAQAAAAEAAAADAAAAAQAAAAsAAACdAAAAvQAAAAEAAAAZAAAANQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAJQAAAFMAAABNAAAAVwAAAI0AAADVAAAA/wAAAN0AAAAtAAAAAQAAAAUAAAADAAA
AAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAQAAAAEAAAATAAAABQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAC9AAAA/wAAAP8AAAD/AAAA/wAAAN8AAABtAAAACwAAAAEAAAADA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAEAAAAB
AAAAAQAAAAMAAAABAAAAAQAAAAEAAAABAAAAAQAAACkAAABfAAAAcQAAAG0AAABBAAAABwAAAAEAAAA
BAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAABQAAAAU
AAAAFAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
B64

write_b64 "$APP_DIR/resources/cat/light_cat_4.ico" << 'B64'
AAABAAIAEBAAAAEAIABoBAAAJgAAACAgAAABACAAqBAAAI4EAAAoAAAAEAAAACAAAAABACAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAADAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAUAAAAFAAAAAQAAAAEAAAADAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAwAAAAEAAAABAAAAAQAAAEUAAABRAAAAAQAAAAMAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAwAAAAEAAAAHAAAAiwAAAC8AAADjAAAAdQAAAAEAAAAFAAAAAQAAAAEAAAABAAAAAwAAAAUAAAADA
AAAAwAAAAEAAABVAAAA3QAAAP8AAAD1AAAA/wAAAEkAAAABAAAABwAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAcAAAABAAAArQAAAP8AAAD3AAAA/QAAAP8AAAB3AAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
7AAAAYQAAACsAAAABAAAAPwAAAP8AAAD7AAAA/wAAAPsAAAD/AAAA9wAAAMUAAABzAAAAAQAAAAEAAA
B1AAAA5wAAALsAAADdAAAAvwAAAM0AAAD/AAAA+QAAAP0AAAD/AAAA/wAAAPUAAADxAAAA2QAAAD0AA
AABAAAAIwAAAA8AAAABAAAADwAAAH0AAADZAAAA/wAAAP8AAAD/AAAA2wAAAP8AAADRAAAAlQAAAKkA
AAAjAAAAAQAAAAEAAAABAAAABQAAAAEAAAABAAAAAQAAADsAAABxAAAATQAAAAEAAABlAAAAyQAAAPE
AAAC5AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAABQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAH
MAAABdAAAAYwAAAAcAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAUAAAADAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAwAAAAEAAAADAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoAAAAIAAAAEAAAAABACAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAADAAAAAQAAAAEAAAABAAAADQAAACUAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAQAAABEAAADHAAA
A7QAAAB0AAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAABQAAAAEAAAAjAAAAMQAAAAMAAAABA
AAAiwAAAP8AAADLAAAABwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAGwAAAOMAAAD
/AAAAjwAAAA0AAADdAAAA/wAAAJkAAAABAAAAAwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAATwAAAIUAA
ADJAAAA/wAAAP8AAAD/AAAA1QAAAPcAAAD/AAAAjwAAAAEAAAADAAAAAQAAAAEAAAABAAAAAQAAAAEA
AAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAQAAADE
AAAD9AAAA/wAAAP8AAAD9AAAA/wAAAP8AAAD/AAAA/QAAAP8AAACnAAAAAQAAAAMAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AMAAAABAAAAJwAAAPkAAAD9AAAA/QAAAP8AAAD/AAAA/wAAAP0AAAD9AAAA/wAAALcAAAABAAAABQAA
AAUAAAADAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAAADAAAAAwAAAAMAAAADAAAAAQA
AAAEAAAABAAAAAwAAAAEAAAB1AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA6w
AAACUAAAABAAAAAQAAAAEAAAADAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAwAAAAcAAAABAAAAVQAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA
/wAAAP0AAAD/AAAA3QAAAIsAAABnAAAALwAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA3AAA
AhwAAAJMAAACNAAAAVwAAABUAAAABAAAAAQAAAAEAAADDAAAA/wAAAP0AAAD/AAAA/wAAAP8AAAD/AA
AA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD7AAAAhQAAAAEAAAABAAAAAQAAAAEAAAALA
AAAiwAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA4wAAAKEAAABRAAAAMQAAAOsAAAD/AAAA/wAAAP8AAAD/
AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/QAAAP8AAAD/AAAAWQAAAAEAAAA
DAAAAAQAAAD8AAAD/AAAA7wAAAI0AAABlAAAAcwAAAKsAAAD7AAAA/wAAAP8AAADjAAAA+QAAAP8AAA
D/AAAA/wAAAP8AAAD/AAAA/wAAAP0AAAD9AAAA/wAAAP8AAAD/AAAA8wAAAMkAAAD/AAAApwAAAHcAA
ACrAAAAAQAAAAEAAAABAAAABwAAAE8AAAApAAAAAQAAAAEAAAABAAAAAQAAAC0AAACXAAAA8QAAAP8A
AAD/AAAA/wAAAP0AAAD9AAAA/QAAAP0AAAD9AAAA/wAAAP8AAAD/AAAA+wAAAP8AAACjAAAAAQAAANU
AAACHAAAAMwAAAIkAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAwAAAAMAAAADAAAAAQAAAA
EAAAAnAAAAfwAAANEAAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAADXAAAAtQAAAPUAAAD/AAAA/wAAA
NcAAABpAAAA6QAAAP8AAADJAAAAJQAAAAEAAAADAAAAAQAAAAEAAAADAAAAAwAAAAEAAAABAAAAAQAA
AAEAAAADAAAAAwAAAAEAAAABAAAACQAAAEUAAACTAAAAxQAAANUAAAC5AAAAXwAAABEAAAABAAAAQwA
AAPEAAACVAAAA5wAAAP8AAADxAAAA+QAAAHkAAAABAAAABQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAwAAAAMAAAABAAAAAQAAAAEAAAABAAAACwAAAAEAAAABAAAAA
QAAAAMAAAABAAAAhQAAAKkAAABnAAAA3QAAANMAAACZAAAAiwAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAADAAAAAwAAAAEAAAABAAA
AAQAAAAMAAAABAAAAAQAAAAEAAAABAAAAlQAAAP8AAAB9AAAATQAAAPUAAACvAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAfwAAAG0AAAABAAAAOwAAADkAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMAAA
ABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAA
AABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAMA
AAABAAAAAQAAAAMAAAADAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAA
EAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAA
AEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAA
AAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQA
AAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQ
AAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAA
AQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAA
AAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAA
AAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABA
AAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAB
AAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
B64

write_b64 "$APP_DIR/resources/icon.png" << 'B64'
iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAYAAABccqhmAAAGFklEQVR4nO3dsYscdRjG8fnJkUKCBIs
gYpEipEiRSoKEIEHEyiJYiIVI/oBUqUTEQsTKwkokiEgKkSAiIhKCWEgQCxEJIiIiEkRSiAQROSTktU
mnmddjsrd393w+cNUzszcofDOwc7tjmqYxAZHuWfcFAOsjABBMACCYAEAwAYBgAgDBBACCCQAEEwAIJ
gAQTAAgmABAMAGAYAIAwQQAggkABBMACCYAEEwAIJgAQDABgGACAMEEAIIJAAQTAAgmABBMACCYAEAw
AYBgAgDBBACCCQAEEwAIJgAQTAAgmABAMAGAYAIAwQQAggkABBMACCYAEEwAIJgAQDABgGACAMEEAII
JAAQTAAgmABBMACCYAEAwAYBgAgDBBACCbaz7AmCJqvqoOeTtuXGM8WHz+teb17/UvP6Z5vy1cgcAwQ
QAggkABBMACCYAEEwAIJgAQDDPAbCjVdXLzSFPNvuV5vVfbc6/2ex/NvuO5g4AggkABBMACCYAEEwAI
JgAQDABgGCeA2Ctqupkc8jpZn+q2S80+/5m/7rZjzb7juYOAIIJAAQTAAgmABBMACCYAEAwAYBg4/YP
rEVVvd8ccqDZrzX7mf99Matxdm4cY7yxXRfyX9wBQDABgGACAMEEAIIJAAQTAAgmABDMcwCsVFUdaA7
p3sfv/l6/c67Zv232y81+pNkfb/ZZY4w3l5zfcQcAwQQAggkABBMACCYAEEwAIJgAQDDfC8CqnW/2pe
/zd76cG8cYs3tVda//ULMfa/YTze45AGA1BACCCQAEEwAIJgAQTAAgmABAMM8B7HBV9VxzyOlmP9zsN
5r9u2bv3ud+pNlX7ZO5sao2F77+ZwvPf23h+Yu4A4BgAgDBBACCCQAEEwAIJgAQTAAgWPz3AlRV9/fc
Dzf7oWa/2ezPNvvxZmdnu9rss/9/xxh/38Vr+Rd3ABBMACCYAEAwAYBgAgDBBACCCQAE2/WfB1BVjzW
HvNDs3flk+6vZ32r2c3PjGOPW1i7n7nIHAMEEAIIJAAQTAAgmABBMACCYAECw9jmAqpo9Zowx+/fuVd
VF5tFmf77Zn2j2zuVmn/1c+WmaDjZ79xwC6/Vjs5+aG8cYv969S9l+7gAgmABAMAGAYAIAwQQAggkAB
BMACLZRVT81xzwwN1bV9eb8Q1u6oq37oNlfmRvHGN8s+eVV9WBziOcAdrYLc+Nuf5+/4w4AggkABBMA
CCYAEEwAIJgAQDABgGAb0zRda445tHD/udkvNvs7c+MY4/vm/HXrvt9937ZcBXdyY90XsE7uACCYAEA
wAYBgAgDBBACCCQAEEwAINm7/3FFV3de8xuz73GOMza1e1F5SVZeaQ5Z+r8G6fdzsXzX7qYX7Usfnxj
FGd/27mjsACCYAEEwAIJgAQDABgGACAMEEAIJtdAeMMf7YjgvZw3b7f7+X5sYxxuz3LnSq6vXmkN+bv
ftH7PO5ca+/z99xBwDBBACCCQAEEwAIJgAQTAAgmABAsPY5ABY7svD8X5r9QLPvX/j7ry48v/N0sy/9
R+rFhefvae4AIJgAQDABgGACAMEEAIIJAAQTAAjmOYDVu9jsx5q9+3v4o83+abPPfi7+NE3n58aqmv1
egDHGreb17232H5p99vMIxhhXmvOjuQOAYAIAwQQAggkABBMACCYAEEwAINi4/cOKVNW+5pDNhb/i5N
w4xvhibq+qd5vXP9zsJ5rff7M5nzVyBwDBBACCCQAEEwAIJgAQTAAgmABAMM8BrFlVPdMc0r1P3zk4N
44xflv4+uxi7gAgmABAMAGAYAIAwQQAggkABBMACOZ7AdZsjPHe3F5V9zcvcbbZZ58DmKbJcwDB3AFA
MAGAYAIAwQQAggkABBMACCYAEMznAUAwdwAQTAAgmABAMAGAYAIAwQQAggkABBMACCYAEEwAIJgAQDA
BgGACAMEEAIIJAAQTAAgmABBMACCYAEAwAYBgAgDBBACCCQAEEwAIJgAQTAAgmABAMAGAYAIAwQQAgg
kABBMACCYAEEwAIJgAQDABgGACAMEEAIIJAAQTAAgmABBMACCYAEAwAYBgAgDBBACCCQAE+wd93aBbK
OqqnQAAAABJRU5ErkJggg==
B64

cat > "$APP_DIR/start-linux.sh" << 'START'
#!/usr/bin/env bash
set -euo pipefail

# Resolve the real script path even when launched through a symlink
# (for example ~/.local/bin/runcat-lumina).
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  case "$SOURCE" in
    /*) ;;
    *) SOURCE="$DIR/$SOURCE" ;;
  esac
done
ROOT="$(cd "$(dirname "$SOURCE")" && pwd)"
cd "$ROOT"

if [ ! -f "$ROOT/main.py" ]; then
  echo "Run this from the RunCat Lumina folder."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required."
  echo "Ubuntu/Debian: sudo apt install python3 python3-venv python3-pip"
  exit 1
fi

VENV_PY="$ROOT/.venv/bin/python"

if [ ! -x "$VENV_PY" ]; then
  echo "First-time setup: creating virtual environment..."
  python3 -m venv "$ROOT/.venv"
fi

# Install the dependencies unless they are already importable. This makes the
# launcher self-healing if the venv exists but packages are missing.
if ! "$VENV_PY" -c "import PIL, psutil, pystray" >/dev/null 2>&1; then
  echo "Installing dependencies..."
  "$VENV_PY" -m pip install -q --upgrade pip
  "$VENV_PY" -m pip install -q -r "$ROOT/requirements.txt"
fi

exec "$VENV_PY" "$ROOT/main.py" "$@"
START
chmod +x "$APP_DIR/start-linux.sh"

echo "Installing Python packages..."
if [ ! -x "$APP_DIR/.venv/bin/python" ]; then
  python3 -m venv "$APP_DIR/.venv"
fi
"$APP_DIR/.venv/bin/python" -m pip install -q --upgrade pip
"$APP_DIR/.venv/bin/python" -m pip install -q -r "$APP_DIR/requirements.txt"

ln -sfn "$APP_DIR/start-linux.sh" "$BIN_DIR/runcat-lumina"
cp "$APP_DIR/resources/icon.png" "$ICON_DIR/runcat-lumina.png"

cat > "$APP_MENU/runcat-lumina.desktop" << DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=RunCat Lumina
GenericName=CPU Cat
Comment=Running cat on the Linux taskbar with custom colors
Exec="$APP_DIR/start-linux.sh"
TryExec="$APP_DIR/start-linux.sh"
Path=$APP_DIR
Icon=$ICON_DIR/runcat-lumina.png
Terminal=false
Categories=Utility;Monitor;
Keywords=cat;cpu;taskbar;tray;runcat;lumina;
StartupNotify=false
StartupWMClass=RunCat_Lumina
DESKTOP
chmod +x "$APP_MENU/runcat-lumina.desktop"

echo
echo "Installed to $APP_DIR"
echo "Start:  bash ~/RunCatLumina/start-linux.sh"
echo "Or:     runcat-lumina"
echo
exec "$APP_DIR/.venv/bin/python" "$APP_DIR/main.py"
