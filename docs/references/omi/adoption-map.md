# Mapa de adopción de Omi

## Objetivo

Dejar claro qué piezas de Omi entran en NicoBot ya, cuáles se posponen y cuáles no vamos a usar.

## Copiar o adaptar en v1

### Floating bar

Estado:

- adaptar

Motivo:

- Omi resuelve muy bien el patrón de presencia mínima y expansión rápida.

### Panel del agente

Estado:

- adaptar

Motivo:

- su estructura conversacional es la referencia principal para NicoBot.

### Estructura conversacional

Estado:

- adaptar

Motivo:

- historial scrollable, respuesta principal clara y follow-up persistente encajan con la v1.

### Estados visuales del agente

Estado:

- adaptar

Motivo:

- Omi diferencia bien espera, thinking y respuesta sin abusar de logs.

## Posponer para fases posteriores

### Screen capture

Estado:

- posponer

Motivo:

- útil para futuro contexto visual, pero fuera del scope de la v1.

### Permisos macOS ligados a captura

Estado:

- posponer

Motivo:

- no hacen falta mientras no haya screenshot ni contexto visual.

### Helper Swift

Estado:

- posponer

Motivo:

- puede ser necesario más adelante, pero no bloquea la primera entrega por hotkeys.

## Descartar por ahora

### Backend cloud y auth

Estado:

- descartar

Motivo:

- añaden complejidad ajena al objetivo del repo.

### Infraestructura remota de agentes

Estado:

- descartar

Motivo:

- la v1 se orienta a una ejecución local y a una integración directa con Hermes.

## Regla de adopción

Toda pieza tomada de Omi debe justificarse por una de estas razones:

- mejora visible del flujo de agente
- reducción de incertidumbre en UX desktop
- preparación para futuras fases sin meter complejidad prematura
