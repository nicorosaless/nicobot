# Arquitectura oficial de la v1

## Resumen

La v1 de NicoBot se apoya en una arquitectura simple:

- `Electron UI` como superficie principal de producto.
- `Hermes Agent` como orquestador conversacional.
- `Runtime local` para ejecutar el agente y exponer su estado a la UI.

El objetivo es lanzar un agente visual sólido antes de reintroducir voz, captura o componentes nativos.

## Componentes

### Electron UI

Responsabilidades:

- registrar hotkeys
- abrir y cerrar la barra/panel del agente
- renderizar greeting, historial, respuestas y errores
- mantener el estado visual del agente
- ofrecer una vista secundaria de diagnóstico cuando haga falta

### Hermes Agent

Responsabilidades:

- generar el greeting inicial
- recibir prompts del usuario
- producir respuestas renderizables
- exponer estados legibles por la UI
- devolver errores user-friendly

### Runtime local

Responsabilidades:

- alojar Hermes Agent
- exponer bridge local o IPC hacia Electron
- mantener sesión mínima de conversación
- desacoplar la UI de la implementación concreta del agente

## Flujo principal

1. El usuario pulsa la hotkey.
2. La UI abre la barra o panel del agente.
3. NicoBot muestra un greeting inicial.
4. El usuario escribe una petición en el panel.
5. Hermes cambia a estado `thinking`.
6. La respuesta se renderiza en el historial y la UI pasa a `responding`.
7. El usuario puede continuar la conversación o cerrar el panel.

## Exclusiones explícitas de la v1

- sin grabación
- sin STT/TTS
- sin screen capture
- sin permisos de micrófono o screen recording
- sin helper Swift como dependencia de la primera entrega

## Fases posteriores ya previstas

- contexto visual mediante captura de pantalla
- integración progresiva del backend de voz existente
- posible helper Swift si la UX macOS o los permisos lo justifican
