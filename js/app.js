const FRAME_COUNT = 5;
const SCALE = 8;
const INTERVALS = [0.5, 0.3, 0.2, 0.1, 0.07];

const PRESETS = [
  { name: "Original White", color: "#FFFFFF" },
  { name: "Original Black", color: "#111111" },
  { name: "Ginger", color: "#D2691E" },
  { name: "Orange Tabby", color: "#FF9F43" },
  { name: "Cream", color: "#F6D7A7" },
  { name: "Gray", color: "#8B93A7" },
  { name: "Siamese", color: "#C4A484" },
  { name: "Calico", color: "#C75B39" },
  { name: "Pink", color: "#FF7AA2" },
  { name: "Sky", color: "#5B9DFF" }
];

const state = {
  color: "#FFFFFF",
  name: "Original White",
  cpu: 12,
  autoCpu: true,
  positive: true,
  frame: 0,
  lastTick: 0,
  images: []
};

const catCanvas = document.getElementById("catCanvas");
const trayCanvas = document.getElementById("trayCat");
const brandCanvas = document.getElementById("brandCat");
const catCtx = catCanvas.getContext("2d");
const trayCtx = trayCanvas.getContext("2d");
const brandCtx = brandCanvas.getContext("2d");
const colorPicker = document.getElementById("colorPicker");
const colorHex = document.getElementById("colorHex");
const cpuSlider = document.getElementById("cpuSlider");
const cpuValue = document.getElementById("cpuValue");
const speedLabel = document.getElementById("speedLabel");
const currentSwatch = document.getElementById("currentSwatch");
const currentName = document.getElementById("currentName");
const currentHex = document.getElementById("currentHex");
const presetGrid = document.getElementById("presetGrid");
const clock = document.getElementById("clock");

function hexToRgb(hex) {
  const value = hex.replace("#", "").trim();
  const full = value.length === 3
    ? value.split("").map((c) => c + c).join("")
    : value;
  const n = parseInt(full, 16);
  return {
    r: (n >> 16) & 255,
    g: (n >> 8) & 255,
    b: n & 255
  };
}

function normalizeHex(value) {
  let hex = value.trim().toUpperCase();
  if (!hex.startsWith("#")) hex = `#${hex}`;
  if (/^#[0-9A-F]{3}$/.test(hex)) {
    hex = `#${hex[1]}${hex[1]}${hex[2]}${hex[2]}${hex[3]}${hex[3]}`;
  }
  return /^#[0-9A-F]{6}$/.test(hex) ? hex : null;
}

function tintFrame(image, color) {
  const src = document.createElement("canvas");
  src.width = image.width;
  src.height = image.height;
  const sctx = src.getContext("2d");
  sctx.drawImage(image, 0, 0);
  const data = sctx.getImageData(0, 0, src.width, src.height);
  const { r, g, b } = hexToRgb(color);
  const pixels = data.data;
  for (let i = 0; i < pixels.length; i += 4) {
    if (pixels[i + 3] === 0) continue;
    pixels[i] = r;
    pixels[i + 1] = g;
    pixels[i + 2] = b;
  }
  sctx.putImageData(data, 0, 0);
  return src;
}

function drawSprite(ctx, canvas, sprite) {
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.imageSmoothingEnabled = false;
  const size = canvas.width;
  ctx.drawImage(sprite, 0, 0, size, size);
}

function currentInterval() {
  const list = state.positive ? INTERVALS : [...INTERVALS].reverse();
  if (state.cpu < 10) return list[0];
  if (state.cpu < 20) return list[1];
  if (state.cpu < 40) return list[2];
  if (state.cpu < 60) return list[3];
  return list[4];
}

function renderFrame() {
  if (!state.images.length) return;
  const sprite = tintFrame(state.images[state.frame], state.color);
  drawSprite(catCtx, catCanvas, sprite);
  drawSprite(trayCtx, trayCanvas, sprite);
  drawSprite(brandCtx, brandCanvas, sprite);
}

function setColor(color, name) {
  const hex = normalizeHex(color);
  if (!hex) return;
  state.color = hex;
  if (name) state.name = name;
  else {
    const match = PRESETS.find((p) => p.color.toUpperCase() === hex);
    state.name = match ? match.name : "Custom";
  }
  colorPicker.value = hex;
  colorHex.value = hex;
  currentSwatch.style.background = hex;
  currentName.textContent = state.name;
  currentHex.textContent = hex;
  document.querySelectorAll(".preset").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.color.toUpperCase() === hex);
  });
  renderFrame();
}

function setCpu(value) {
  state.cpu = Number(value);
  cpuSlider.value = String(state.cpu);
  cpuValue.textContent = `${state.cpu}%`;
  speedLabel.textContent = `${currentInterval().toFixed(2)}s / frame`;
  document.getElementById("catCanvas").style.animationDuration = `${Math.max(1.4, 8 - state.cpu / 16)}s`;
}

function tick(now) {
  const intervalMs = currentInterval() * 1000;
  if (now - state.lastTick >= intervalMs) {
    state.frame = (state.frame + 1) % FRAME_COUNT;
    state.lastTick = now;
    renderFrame();
  }
  requestAnimationFrame(tick);
}

function updateClock() {
  const now = new Date();
  clock.textContent = now.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function simulateCpu() {
  if (!state.autoCpu) return;
  const drift = Math.round((Math.random() - 0.45) * 8);
  setCpu(Math.min(96, Math.max(3, state.cpu + drift)));
}

function buildPresets() {
  PRESETS.forEach((preset) => {
    const btn = document.createElement("button");
    btn.className = "preset";
    btn.type = "button";
    btn.title = preset.name;
    btn.dataset.color = preset.color;
    btn.style.setProperty("--swatch", preset.color);
    btn.addEventListener("click", () => setColor(preset.color, preset.name));
    presetGrid.appendChild(btn);
  });
}

async function loadFrames() {
  const loads = Array.from({ length: FRAME_COUNT }, (_, i) => {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = `cat/dark_cat_${i}.png`;
    });
  });
  state.images = await Promise.all(loads);
  catCanvas.width = 32 * SCALE;
  catCanvas.height = 32 * SCALE;
}

async function init() {
  buildPresets();
  await loadFrames();
  setColor("#FFFFFF", "Original White");
  setCpu(12);
  updateClock();
  setInterval(updateClock, 1000);
  setInterval(simulateCpu, 1400);
  requestAnimationFrame(tick);

  colorPicker.addEventListener("input", (e) => setColor(e.target.value, "Custom"));
  colorHex.addEventListener("change", (e) => {
    const hex = normalizeHex(e.target.value);
    if (hex) setColor(hex, "Custom");
    else colorHex.value = state.color;
  });
  cpuSlider.addEventListener("input", (e) => {
    state.autoCpu = false;
    document.getElementById("autoCpu").checked = false;
    setCpu(e.target.value);
  });
  document.getElementById("autoCpu").addEventListener("change", (e) => {
    state.autoCpu = e.target.checked;
  });
  document.getElementById("positiveCorr").addEventListener("change", (e) => {
    state.positive = e.target.checked;
    setCpu(state.cpu);
  });
  document.getElementById("darkBg").addEventListener("change", (e) => {
    document.body.classList.toggle("light", !e.target.checked);
  });

  const osLabels = { windows: "Win", linux: "Linux", macos: "macOS" };

  function setOs(os) {
    document.body.classList.remove("os-windows", "os-linux", "os-macos");
    document.body.classList.add(`os-${os}`);
    document.querySelectorAll(".os-btn").forEach((item) => {
      item.classList.toggle("active", item.dataset.os === os);
    });
    document.getElementById("osMark").textContent = osLabels[os];
  }

  function detectOs() {
    const ua = navigator.userAgent.toLowerCase();
    if (ua.includes("mac")) return "macos";
    if (ua.includes("linux")) return "linux";
    return "windows";
  }

  setOs(detectOs());
  document.getElementById("osSwitch").addEventListener("click", (e) => {
    const btn = e.target.closest(".os-btn");
    if (!btn) return;
    setOs(btn.dataset.os);
  });
}

init();
