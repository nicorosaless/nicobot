const statePill = document.getElementById("statePill");
const openAgentBtn = document.getElementById("openAgentBtn");
const closeAgentBtn = document.getElementById("closeAgentBtn");
const resetBtn = document.getElementById("resetBtn");
const toggleDebugBtn = document.getElementById("toggleDebugBtn");
const setHotkeyBtn = document.getElementById("setHotkeyBtn");
const hotkeySelect = document.getElementById("hotkeySelect");
const agentPanel = document.getElementById("agentPanel");
const debugPanel = document.getElementById("debugPanel");
const sessionLabel = document.getElementById("sessionLabel");
const messagesEl = document.getElementById("messages");
const eventsEl = document.getElementById("events");
const promptInput = document.getElementById("promptInput");
const composerForm = document.getElementById("composerForm");
const sendBtn = document.getElementById("sendBtn");
const errorBanner = document.getElementById("errorBanner");

let currentState = null;

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function formatMultiline(text) {
  return escapeHtml(text).replace(/\n/g, "<br />");
}

function setPanelOpen(isOpen) {
  agentPanel.classList.toggle("closed", !isOpen);
}

function renderMessages(messages) {
  if (!messages?.length) {
    messagesEl.innerHTML = `
      <article class="message assistant">
        <div class="message-meta">Hermes</div>
        <div class="message-body">Todavia no hay mensajes en esta sesion.</div>
      </article>
    `;
    return;
  }

  messagesEl.innerHTML = messages
    .map((item) => {
      const roleLabel = item.role === "user" ? "You" : "Hermes";
      const extraClass = item.kind === "error" ? " is-error" : "";
      return `
        <article class="message ${item.role}${extraClass}">
          <div class="message-meta">${roleLabel}</div>
          <div class="message-body">${formatMultiline(item.content)}</div>
        </article>
      `;
    })
    .join("");

  messagesEl.scrollTop = messagesEl.scrollHeight;
}

function renderEvents(events) {
  if (!events?.length) {
    eventsEl.innerHTML = '<p class="event-empty">Sin eventos todavia.</p>';
    return;
  }

  eventsEl.innerHTML = events
    .map(
      (item) => `
        <div class="event">
          <div class="event-kind">${escapeHtml(item.kind)} · ${new Date(item.at).toLocaleTimeString()}</div>
          <div class="event-msg">${escapeHtml(item.message)}</div>
        </div>
      `
    )
    .join("");
}

function renderError(message) {
  if (!message) {
    errorBanner.classList.add("hidden");
    errorBanner.textContent = "";
    return;
  }

  errorBanner.classList.remove("hidden");
  errorBanner.textContent = message;
}

function updateComposerState(state) {
  const isBusy = state.appState === "thinking";
  sendBtn.disabled = isBusy;
  promptInput.disabled = false;
  promptInput.setAttribute(
    "placeholder",
    isBusy
      ? "Hermes esta pensando..."
      : "Escribe lo que necesitas y Hermes te responde aqui."
  );
}

function renderState(state) {
  currentState = state;

  statePill.textContent = state?.appState || "idle";
  statePill.className = `pill ${state?.appState || "idle"}`;

  setPanelOpen(Boolean(state?.panelOpen));
  openAgentBtn.textContent = state?.panelOpen ? "Hide agent" : "Open agent";

  if (hotkeySelect && state?.hotkey) {
    const options = Array.from(hotkeySelect.options).map((item) => item.value);
    if (!options.includes(state.hotkey)) {
      const opt = document.createElement("option");
      opt.value = state.hotkey;
      opt.textContent = state.hotkey;
      hotkeySelect.appendChild(opt);
    }
    hotkeySelect.value = state.hotkey;
  }

  sessionLabel.textContent = state?.sessionId || "session";
  renderMessages(state?.messages || []);
  renderEvents(state?.events || []);
  renderError(state?.lastError || null);
  updateComposerState(state);
}

openAgentBtn.addEventListener("click", async () => {
  await window.nicobot.toggleAgent();
});

closeAgentBtn.addEventListener("click", async () => {
  await window.nicobot.closeAgent();
});

resetBtn.addEventListener("click", async () => {
  promptInput.value = "";
  await window.nicobot.resetConversation();
});

toggleDebugBtn.addEventListener("click", () => {
  debugPanel.classList.toggle("hidden");
});

setHotkeyBtn.addEventListener("click", async () => {
  const result = await window.nicobot.setHotkey(hotkeySelect.value);
  if (!result?.ok) {
    alert(`Could not register hotkey: ${hotkeySelect.value}`);
  }
});

composerForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const prompt = promptInput.value.trim();
  if (!prompt) return;

  const result = await window.nicobot.sendPrompt(prompt);
  if (result?.ok) {
    promptInput.value = "";
  }
});

promptInput.addEventListener("keydown", async (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
    event.preventDefault();
    const prompt = promptInput.value.trim();
    if (!prompt) return;

    const result = await window.nicobot.sendPrompt(prompt);
    if (result?.ok) {
      promptInput.value = "";
    }
  }

  if (event.key === "Escape" && currentState?.panelOpen) {
    event.preventDefault();
    await window.nicobot.closeAgent();
  }
});

window.nicobot.onStateUpdate((state) => {
  renderState(state);
});

window.nicobot.onFocusInput(() => {
  if (currentState?.panelOpen) {
    promptInput.focus();
    promptInput.setSelectionRange(promptInput.value.length, promptInput.value.length);
  }
});

window.nicobot.getState().then(renderState);
