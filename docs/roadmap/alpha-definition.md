# Definición de alpha

## Qué significa “v1 usable”

La alpha de NicoBot será usable cuando un usuario pueda invocar el agente con hotkeys, leer un greeting inicial, escribir una petición y mantener una conversación básica dentro de una UI consistente y entendible.

## Checklist de aceptación

- La hotkey abre la UI del agente de forma fiable.
- El greeting inicial aparece automáticamente.
- El panel muestra estados claros: `opened`, `thinking`, `responding`, `error`.
- El usuario puede escribir un prompt y recibir una respuesta dentro del historial.
- El historial se mantiene visualmente coherente tras varias interacciones.
- Los logs técnicos no ocupan la superficie principal.
- El usuario puede cerrar y reabrir el agente sin confusión de estado.
- La documentación deja claro que voz y screen capture son fases posteriores.

## Qué no exige esta alpha

- No exige grabación.
- No exige STT/TTS.
- No exige captura de pantalla.
- No exige helper Swift.
- No exige packaging final de distribución.

## Riesgos que deben vigilarse

- que la UI siga pareciendo una shell temporal
- que el agente mezcle estado visual y logs de depuración
- que el flujo de hotkey no sea consistente
- que la arquitectura se vuelva a sesgar demasiado pronto hacia voz o captura
