# Documentación de NicoBot

Este directorio es la fuente de verdad de producto, arquitectura, roadmap y diseño para NicoBot.

## Producto

- [`product/vision.md`](product/vision.md): visión, usuario objetivo y propuesta de valor.

## Arquitectura

- [`architecture/system-overview.md`](architecture/system-overview.md): arquitectura oficial de la v1.
- [`architecture/local-interfaces.md`](architecture/local-interfaces.md): contratos locales entre UI y agente.

## Roadmap

- [`roadmap/development-roadmap.md`](roadmap/development-roadmap.md): roadmap único del proyecto.
- [`roadmap/alpha-definition.md`](roadmap/alpha-definition.md): definición de “v1 usable”.

## Referencias externas

- [`references/omi/overview.md`](references/omi/overview.md): por qué Omi es una referencia válida.
- [`references/omi/adoption-map.md`](references/omi/adoption-map.md): qué copiamos, adaptamos o descartamos.
- [`references/omi/ui-agent-notes.md`](references/omi/ui-agent-notes.md): patrones visuales e interacción observados en Omi.
- [`references/spokenly-widget-reference.png`](references/spokenly-widget-reference.png): referencia visual adicional para widgets compactos.

## UX/UI

- [`ui/agent-display-spec.md`](ui/agent-display-spec.md): spec principal del display del agente.
- [`ui/floating-bar-spec.md`](ui/floating-bar-spec.md): comportamiento de la barra flotante.

## Defaults de esta etapa

- Idioma principal de docs: español.
- Arquitectura v1: Electron + Hermes Agent.
- Interacción v1: hotkey abre el agente, muestra greeting inicial y luego espera input de texto.
- Queda fuera de v1: grabación, STT/TTS, captura de pantalla y permisos de screen recording.
