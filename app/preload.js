const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("nicobot", {
  getState: () => ipcRenderer.invoke("state:get"),
  toggleRecording: () => ipcRenderer.invoke("backend:toggle-recording"),
  restartBackend: () => ipcRenderer.invoke("backend:restart"),
  setHotkey: (accelerator) => ipcRenderer.invoke("hotkey:set", accelerator),
  onStateUpdate: (handler) => {
    const wrapped = (_event, payload) => handler(payload);
    ipcRenderer.on("state:update", wrapped);
    return () => ipcRenderer.removeListener("state:update", wrapped);
  },
});
