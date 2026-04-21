const { app, BrowserWindow, ipcMain, globalShortcut } = require("electron");
const path = require("path");

let mainWindow = null;
let activeResponseTimer = null;
let activeSettleTimer = null;

const state = {
  appState: "idle",
  panelOpen: false,
  hotkey: "CommandOrControl+Shift+Space",
  hotkeyRegistered: false,
  sessionId: createSessionId(),
  greetingShown: false,
  messages: [],
  events: [],
  lastError: null,
};

function createSessionId() {
  return `session-${Date.now()}`;
}

function emitState() {
  if (!mainWindow) return;
  mainWindow.webContents.send("state:update", {
    ...state,
    messages: [...state.messages],
    events: [...state.events],
  });
}

function focusPrompt() {
  if (!mainWindow) return;
  mainWindow.webContents.send("agent:focus-input");
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

function addMessage(role, content, kind = "message") {
  state.messages.push({
    id: `${role}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    role,
    kind,
    content,
    at: new Date().toISOString(),
  });
}

function greetingText() {
  return [
    "Hola, soy Hermes dentro de NicoBot.",
    "Puedo ayudarte a pensar una tarea, aterrizar una idea de producto, redactar pasos o darte una primera respuesta accionable.",
    "Escribe lo que necesitas y seguimos desde aqui.",
  ].join("\n\n");
}

function ensureGreeting() {
  if (state.greetingShown) return;
  addMessage("assistant", greetingText(), "greeting");
  state.greetingShown = true;
  pushEvent("system", "Greeting inicial preparado");
}

function setAgentState(nextState) {
  state.appState = nextState;
  emitState();
}

function cancelPendingAgentWork() {
  if (activeResponseTimer) {
    clearTimeout(activeResponseTimer);
    activeResponseTimer = null;
  }
  if (activeSettleTimer) {
    clearTimeout(activeSettleTimer);
    activeSettleTimer = null;
  }
}

function buildAgentResponse(prompt) {
  const text = prompt.trim();
  const lower = text.toLowerCase();

  if (!text) {
    return "No he recibido contenido. Escribe una peticion y te respondo aqui mismo.";
  }

  if (lower.includes("error")) {
    throw new Error("Error de prueba solicitado desde el prompt.");
  }

  if (lower.includes("roadmap") || lower.includes("plan")) {
    return [
      "Te propongo un siguiente paso muy concreto:",
      "1. Cerrar el flujo principal del agente: abrir, greeting, prompt, respuesta.",
      "2. Afinar la UI hasta que se sienta compacta y clara.",
      "3. Integrar una primera capa real de Hermes manteniendo este mismo contrato.",
    ].join("\n");
  }

  if (lower.includes("ui") || lower.includes("interfaz") || lower.includes("omi")) {
    return [
      "Para esta v1, mantendria la interfaz en tres piezas:",
      "- barra compacta siempre visible",
      "- panel expandido con historial limpio",
      "- input inferior persistente para el follow-up",
      "",
      "Eso nos deja una experiencia muy cercana a Omi, pero ya con lenguaje y branding de NicoBot.",
    ].join("\n");
  }

  if (lower.includes("hermes")) {
    return [
      "Hermes puede vivir bien en esta arquitectura.",
      "La UI solo necesita cuatro cosas del agente: greeting, estado, respuesta y error user-friendly.",
      "Con eso podemos iterar la interfaz sin bloquear la integracion real del runtime.",
    ].join("\n");
  }

  return [
    `He recibido: "${text}"`,
    "",
    "En esta v1 estoy funcionando como agente textual por hotkeys.",
    "Puedo ayudarte a probar el panel, el flujo conversacional y la experiencia general antes de meter voz o captura de pantalla.",
  ].join("\n");
}

function openAgent(source = "ui") {
  if (mainWindow) {
    if (mainWindow.isMinimized()) {
      mainWindow.restore();
    }
    mainWindow.show();
    mainWindow.focus();
  }

  state.panelOpen = true;
  state.lastError = null;
  ensureGreeting();
  if (state.appState === "idle" || state.appState === "error") {
    state.appState = "opened";
  }
  pushEvent("system", `Agente abierto desde ${source}`);
  emitState();
  focusPrompt();
}

function closeAgent(source = "ui") {
  cancelPendingAgentWork();
  state.panelOpen = false;
  state.appState = "idle";
  state.lastError = null;
  pushEvent("system", `Agente cerrado desde ${source}`);
  emitState();
}

function toggleAgent(source = "ui") {
  if (state.panelOpen) {
    closeAgent(source);
  } else {
    openAgent(source);
  }
}

function resetConversation() {
  cancelPendingAgentWork();
  state.sessionId = createSessionId();
  state.messages = [];
  state.greetingShown = false;
  state.lastError = null;
  state.appState = state.panelOpen ? "opened" : "idle";
  pushEvent("system", "Sesion reiniciada");
  if (state.panelOpen) {
    ensureGreeting();
    focusPrompt();
  }
  emitState();
}

function submitPrompt(prompt) {
  const trimmed = String(prompt || "").trim();
  if (!trimmed) {
    return { ok: false, error: "Prompt vacio" };
  }

  if (!state.panelOpen) {
    openAgent("implicit-submit");
  }

  cancelPendingAgentWork();
  state.lastError = null;
  addMessage("user", trimmed, "prompt");
  state.appState = "thinking";
  pushEvent("user", `Prompt enviado: ${trimmed.slice(0, 120)}`);
  emitState();

  activeResponseTimer = setTimeout(() => {
    try {
      const response = buildAgentResponse(trimmed);
      addMessage("assistant", response, "response");
      state.appState = "responding";
      pushEvent("agent", "Respuesta generada");
      emitState();

      activeSettleTimer = setTimeout(() => {
        state.appState = "opened";
        emitState();
        focusPrompt();
        activeSettleTimer = null;
      }, 280);
    } catch (error) {
      state.lastError = error.message;
      state.appState = "error";
      addMessage(
        "assistant",
        "He fallado al procesar este prompt. Puedes reintentarlo o reiniciar la sesion.",
        "error"
      );
      pushEvent("stderr", error.message);
      emitState();
      focusPrompt();
    } finally {
      activeResponseTimer = null;
    }
  }, 950);

  return { ok: true };
}

function registerAgentHotkey(accelerator) {
  try {
    globalShortcut.unregisterAll();
    const ok = globalShortcut.register(accelerator, () => {
      toggleAgent("hotkey");
      pushEvent("system", `Hotkey pulsada: ${accelerator}`);
    });
    state.hotkey = accelerator;
    state.hotkeyRegistered = ok;
    if (!ok) pushEvent("stderr", `No se pudo registrar la hotkey: ${accelerator}`);
    emitState();
    return ok;
  } catch (error) {
    state.hotkeyRegistered = false;
    pushEvent("stderr", `Hotkey error: ${String(error)}`);
    emitState();
    return false;
  }
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1180,
    height: 860,
    minWidth: 980,
    minHeight: 680,
    title: "NicoBot",
    backgroundColor: "#111318",
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

app.whenReady().then(() => {
  createWindow();
  registerAgentHotkey(state.hotkey);
  emitState();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  globalShortcut.unregisterAll();
  cancelPendingAgentWork();
  if (process.platform !== "darwin") app.quit();
});

ipcMain.handle("state:get", () => state);
ipcMain.handle("agent:open", () => {
  openAgent("ui");
  return { ok: true };
});
ipcMain.handle("agent:close", () => {
  closeAgent("ui");
  return { ok: true };
});
ipcMain.handle("agent:toggle", () => {
  toggleAgent("ui");
  return { ok: true, panelOpen: state.panelOpen };
});
ipcMain.handle("agent:send", (_event, prompt) => {
  return submitPrompt(prompt);
});
ipcMain.handle("agent:reset", () => {
  resetConversation();
  return { ok: true };
});
ipcMain.handle("hotkey:set", (_event, accelerator) => {
  const ok = registerAgentHotkey(accelerator);
  return { ok, accelerator };
});
