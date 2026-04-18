const statePill = document.getElementById("statePill");
const transcriptEs = document.getElementById("transcriptEs");
const translatedEn = document.getElementById("translatedEn");
const metricStt = document.getElementById("metricStt");
const metricTts = document.getElementById("metricTts");
const eventsEl = document.getElementById("events");
const recordBtn = document.getElementById("recordBtn");
const restartBtn = document.getElementById("restartBtn");
const toggleLabel = document.getElementById("toggleLabel");
const hotkeySelect = document.getElementById("hotkeySelect");
const setHotkeyBtn = document.getElementById("setHotkeyBtn");
const conversationPanel = document.getElementById("conversationPanel");
const expandBtn = document.getElementById("expandBtn");

let expanded = false;

function fmtSecs(v) {
  if (typeof v !== "number" || Number.isNaN(v)) return "-";
  return `${v.toFixed(2)}s`;
}

function setText(el, value, emptyText) {
  if (!value) {
    el.textContent = emptyText;
    el.classList.add("empty");
    return;
  }
  el.textContent = value;
  el.classList.remove("empty");
}

function renderEvents(items) {
  eventsEl.innerHTML = "";
  for (const item of items || []) {
    const wrapper = document.createElement("div");
    wrapper.className = "event";

    const kind = document.createElement("div");
    kind.className = "kind";
    kind.textContent = `${item.kind || "log"} · ${new Date(item.at).toLocaleTimeString()}`;

    const msg = document.createElement("div");
    msg.className = "msg";
    msg.textContent = item.message || "";

    wrapper.appendChild(kind);
    wrapper.appendChild(msg);
    eventsEl.appendChild(wrapper);
  }
}

function renderState(s) {
  const appState = s?.appState || "idle";
  statePill.textContent = appState;
  statePill.className = `pill ${appState}`;

  if (toggleLabel) {
    toggleLabel.textContent =
      appState === "recording" ? "Stop recording" : "Start recording";
  }

  if (hotkeySelect && s?.hotkey) {
    const options = Array.from(hotkeySelect.options).map((o) => o.value);
    if (!options.includes(s.hotkey)) {
      const opt = document.createElement("option");
      opt.value = s.hotkey;
      opt.textContent = s.hotkey;
      hotkeySelect.appendChild(opt);
    }
    hotkeySelect.value = s.hotkey;
  }

  setText(transcriptEs, s?.transcriptEs, "No transcript yet.");
  setText(translatedEn, s?.translatedEn, "No translated text yet.");

  metricStt.textContent = fmtSecs(s?.lastTimings?.stt);
  metricTts.textContent = fmtSecs(s?.lastTimings?.tts);

  renderEvents(s?.events || []);
}

function renderExpandState() {
  if (!conversationPanel || !expandBtn) return;
  if (expanded) {
    conversationPanel.classList.remove("collapsed");
    expandBtn.textContent = "Hide conversation";
  } else {
    conversationPanel.classList.add("collapsed");
    expandBtn.textContent = "Show conversation";
  }
}

recordBtn.addEventListener("click", async () => {
  await window.nicobot.toggleRecording();
});

restartBtn.addEventListener("click", async () => {
  await window.nicobot.restartBackend();
});

setHotkeyBtn.addEventListener("click", async () => {
  const value = hotkeySelect.value;
  const result = await window.nicobot.setHotkey(value);
  if (!result?.ok) {
    alert(`Could not register hotkey: ${value}`);
  }
});

expandBtn.addEventListener("click", () => {
  expanded = !expanded;
  renderExpandState();
});

window.nicobot.onStateUpdate((s) => {
  renderState(s);
});

window.nicobot.getState().then(renderState);
renderExpandState();
