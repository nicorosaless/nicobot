const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("nicobot", {
  getState: () => ipcRenderer.invoke("state:get"),
  openAgent: () => ipcRenderer.invoke("agent:open"),
  closeAgent: () => ipcRenderer.invoke("agent:close"),
  toggleAgent: () => ipcRenderer.invoke("agent:toggle"),
  sendPrompt: (prompt) => ipcRenderer.invoke("agent:send", prompt),
  resetConversation: () => ipcRenderer.invoke("agent:reset"),
  setHotkey: (accelerator) => ipcRenderer.invoke("hotkey:set", accelerator),
  onStateUpdate: (handler) => {
    const wrapped = (_event, payload) => handler(payload);
    ipcRenderer.on("state:update", wrapped);
    return () => ipcRenderer.removeListener("state:update", wrapped);
  },
  onFocusInput: (handler) => {
    const wrapped = () => handler();
    ipcRenderer.on("agent:focus-input", wrapped);
    return () => ipcRenderer.removeListener("agent:focus-input", wrapped);
  },
});
