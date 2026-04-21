# Visión de producto

## Qué es NicoBot

NicoBot es un asistente de escritorio para macOS que debe sentirse inmediato, local y útil durante el trabajo diario. La primera versión no intenta resolver toda la cadena multimodal; se centra en hacer muy bien un agente visual que aparece con hotkeys y responde dentro de una UI ligera.

## Usuario objetivo

- Persona que trabaja muchas horas en macOS y quiere invocar un asistente sin cambiar de contexto.
- Usuario que valora velocidad, claridad visual y baja fricción.
- Equipo pequeño que prioriza shipping iterativo antes que una plataforma compleja desde el día uno.

## Propuesta de valor

- Abrir el agente al instante con hotkeys.
- Tener una conversación clara dentro de un panel compacto y expandible.
- Construir una base de producto sólida antes de añadir voz, captura de pantalla y automatización más avanzada.

## Principio de diseño de la v1

La v1 debe ser un agente rápido y usable por hotkeys. Eso implica:

- abrir rápido
- orientar al usuario con un greeting inicial
- mantener el foco en la conversación
- evitar logs, métricas y paneles técnicos en la superficie principal
- dejar preparada la arquitectura para sumar contexto visual y voz más adelante

## Qué no intenta resolver esta versión

- No incluye grabación ni escucha activa.
- No integra STT/TTS en el flujo principal del producto.
- No depende de captura de pantalla ni permisos de screen recording.
- No intenta replicar el backend cloud o la complejidad operativa de Omi.
