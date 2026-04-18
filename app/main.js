const { app, BrowserWindow, ipcMain } = require("electron");
const path = require("path");
const { spawn } = require("child_process");

let mainWindow = null;
let backendProcess = null;

const state = {
  appState: "idle",
  transcriptEs: "",
  translatedEn: "",
  lastTimings: null,
  recordingStartedAt: null,
  events: [],
};

function emitState() {
  if (!mainWindow) return;
  mainWindow.webContents.send("state:update", state);
}

function pushEvent(kind, message) {
  state.events.unshift({
    kind,
    message,
    at: new Date().toISOString(),
  });
  state.events = state.events.slice(0, 50);
  emitState();
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1100,
    height: 760,
    minWidth: 980,
    minHeight: 640,
    title: "NicoBot",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, "renderer", "index.html"));

  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

function parseBackendLine(line) {
  const text = line.trim();
  if (!text) return;

  pushEvent("log", text);

  if (text.includes("GRABANDO ACTIVO")) {
    state.appState = "recording";
    state.recordingStartedAt = Date.now();
    emitState();
    return;
  }

  if (text.includes("Grabacion detenida") || text.includes("Procesando")) {
    state.appState = "processing";
    emitState();
    return;
  }

  if (text.startsWith("ES:")) {
    const match = text.match(/ES:\s+"(.*)"/);
    if (match) {
      state.transcriptEs = match[1];
      emitState();
    }
    return;
  }

  if (text.startsWith("EN:")) {
    const match = text.match(/EN:\s+"(.*)"/);
    if (match) {
      state.translatedEn = match[1];
      emitState();
    }
    return;
  }

  if (text.includes("🔈 Reproduciendo")) {
    state.appState = "speaking";
    emitState();
    return;
  }

  if (text.includes("✅ Completado")) {
    state.appState = "idle";
    emitState();
    return;
  }

  if (text.includes("⏱️") && (text.includes("STT") || text.includes("TTS"))) {
    const sttMatch = text.match(/STT:\s+([0-9.]+)s/);
    const ttsMatch = text.match(/TTS:\s+([0-9.]+)s/);
    if (!state.lastTimings) state.lastTimings = {};
    if (sttMatch) state.lastTimings.stt = Number(sttMatch[1]);
    if (ttsMatch) state.lastTimings.tts = Number(ttsMatch[1]);
    emitState();
    return;
  }
}

function startBackend() {
  if (backendProcess) return;

  const repoRoot = path.resolve(__dirname, "..");
  const script = path.join(repoRoot, "spoken_assistant_ptt.py");

  // Prefer local .venv if available; fallback to python3.
  const venvPython = path.join(repoRoot, ".venv", "bin", "python3");
  const pythonCmd = require("fs").existsSync(venvPython) ? venvPython : "python3";

  backendProcess = spawn(pythonCmd, [script], {
    cwd: repoRoot,
    env: { ...process.env, PYTHONUNBUFFERED: "1" },
    stdio: ["pipe", "pipe", "pipe"],
  });

  pushEvent("system", `Backend started with ${pythonCmd}`);

  let stdoutBuf = "";
  backendProcess.stdout.on("data", (chunk) => {
    stdoutBuf += chunk.toString("utf8");
    const lines = stdoutBuf.split(/\r?\n/);
    stdoutBuf = lines.pop() || "";
    for (const line of lines) parseBackendLine(line);
  });

  let stderrBuf = "";
  backendProcess.stderr.on("data", (chunk) => {
    stderrBuf += chunk.toString("utf8");
    const lines = stderrBuf.split(/\r?\n/);
    stderrBuf = lines.pop() || "";
    for (const line of lines) {
      if (!line.trim()) continue;
      pushEvent("stderr", line.trim());
    }
  });

  backendProcess.on("exit", (code, signal) => {
    pushEvent("system", `Backend exited (code=${code}, signal=${signal})`);
    backendProcess = null;
    state.appState = "idle";
    emitState();
  });
}

function stopBackend() {
  if (!backendProcess) return;
  backendProcess.kill("SIGTERM");
  backendProcess = null;
}

function sendToggleKey() {
  if (!backendProcess || !backendProcess.stdin) return;
  // Backend maps both 'r' and ' ' to toggle.
  backendProcess.stdin.write("r");
}

app.whenReady().then(() => {
  createWindow();
  startBackend();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  stopBackend();
  if (process.platform !== "darwin") app.quit();
});

ipcMain.handle("state:get", () => state);
ipcMain.handle("backend:toggle-recording", () => {
  sendToggleKey();
  return true;
});
ipcMain.handle("backend:restart", () => {
  stopBackend();
  startBackend();
  return true;
});
