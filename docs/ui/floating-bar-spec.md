# Spec de la barra flotante

## Objetivo

Definir el comportamiento de la barra flotante de NicoBot como entrada compacta al agente.

## Rol de la barra

- presencia mínima del producto en escritorio
- activación rápida por hotkey
- transición al panel expandido

## Requisitos de comportamiento

- Debe poder existir en estado colapsado sin distraer.
- Debe abrir el panel del agente de forma inmediata.
- Debe sentirse relacionada visualmente con el panel expandido.
- Debe permitir volver al estado compacto sin romper la sesión.

## Relación con el panel

- La barra es el estado compacto.
- El panel es el estado conversacional expandido.
- Ambos deben compartir lenguaje visual y estado del agente.

## Estados de interacción

### Colapsado

- mínima presencia
- sin logs
- sin densidad visual innecesaria

### Abierto

- transición clara hacia el panel
- greeting o historial visible según el estado de la sesión

### Error

- indicador breve en la barra
- detalle del error dentro del panel expandido

## Contenido permitido en la barra

- identidad mínima de NicoBot
- indicación corta de estado
- affordance clara de apertura

## Contenido no permitido en la barra

- consola de eventos
- métricas de backend
- bloques largos de texto
- elementos propios del futuro pipeline de voz
