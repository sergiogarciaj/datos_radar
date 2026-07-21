# Lógica de Clasificación de Interacciones

El proceso de clasificación y categorización de interacciones de Seldon (Radar) se rige por una tubería de transformación de datos (Pipeline) distribuida en tres capas principales: **Calculated**, **Intermedia** y **Third**. 

A continuación se detalla cómo se asignan los atributos de Canal, la tipología de Humano vs. Bot, y de dónde se determinan las categorías temáticas de PCA (Post Call / Text Analytics).

---

## 1. Determinación de Naturaleza y Canal (`is_human` y `canal`)

La base de las interacciones distingue si fueron atendidas por agentes humanos o automatizaciones, y a qué canal de servicio corresponden.

### A. Tipología `is_human` (Definido en `Calculated`)
- **`HUMAN`**: Interacciones provenientes de `conversation_detail_unified` (para Voz y Chat humanos) o que son Tickets/Casos provenientes de `cus_claim`.
- **`NOT_HUMAN`**: Interacciones que un usuario mantuvo exclusivamente con un Voicebot o WhatsApp Bot (vienen de `bot_retention`).
- **`BOTH`**: Interacciones que iniciaron en un Bot y derivaron hacia un Agente Humano (existiendo en ambas tablas).

### B. El Campo final `canal` (Definido en `Third`)
Recién en la tabla final, los múltiples tipos técnicos de orígenes se consolidan en "Los Grandes Canales de Negocio". Cabe destacar que **las interacciones catalogadas como `BOTH` finalmente quedan como `HUMAN`** a nivel de métrica consolidada de atención:
- `channel_type = 'voice'` o `NULL` ➔ **`voz`**
- `channel_type = 'whatsapp'`, `'open'`, o `'bot_wsp'` ➔ **`wsp`**
- `channel_type = 'webmessaging'` ➔ **`chat`**
- Interacciones provenientes directamente de reclamos/casos ➔ **`cases`**

*(Existen reglas de fallback para el `channel_type = 'CC'` donde, dependiendo de si originó o escaló a humano o bot, todo el flujo Legacy de telefonía viaja como `voz`).*

---

## 2. Orígenes de Categorías PCA (Definido en `Calculated`)

Cada conversación intenta asignarse a una categoría (Primera, Segunda y Tercera), que dice "de qué se trató la interacción". El proceso obtiene la información de diferentes orígenes dependendiendo de la metadata disponible:

1. **Voz Humana (`pca_conversation_category`)**: Modelos de transcripción de audio a texto para voz.
2. **Chat Web y WhatsApp Humano (`post_whatsapp_analytics_conversation_category`)**: Modelos NLP aplicados al texto del chat.
3. **Casos / Tickets**: Viene de categorizaciones pre-etiquetadas como `claim_ai_subtypification` y `claim_ai_typification`.
4. **Bots**: Directamente desde la tabla de Bots como `category_voicebot_typification`.

### La Regla de "La Mejor Categoría por Agente"
Un agente humano pudo haber tratado varios temas, y los algoritmos PCA a veces botan basura como `'OTROS'` o `'SIN_CONTEXTO'`.
`Calculated` genera un **ranking inteligente** de categorías priorizando siempre los temas con significado real. Se hace un `ROW_NUMBER()` ordenado de tal forma que toda categorización que **NO** sea `'OTROS'` y **NO** sea `'SIN_CONTEXTO'` le gana jerárquicamente a aquellas que son genéricas.

---

## 3. Resolución de Colisiones en Multipuesto/Chat (`Intermedia`)

En interacciones asíncronas (`webmessaging` y `whatsapp`), es habitual que **varios agentes** participen en una misma `conversation_id`. Sin embargo, los reportes operacionales a nivel de conversación (Dashboard Radar) solo pueden mostrar **UNA** categoría principal por conversación.

¿Mande a cuál agente usamos para etiquetar la categoría del chat general?
**Respuesta: El agente que más trabajó (Mayor AHT).**
1. Agrupa los `skill_lookup` de todos los agentes.
2. Suma todo el `aht` (tiempo de atención) de cada agente.
3. Encuentra al agente "ganador" (`best_agent` con mayor AHT).
4. La Conversación hereda el árbol de categorías (`cat_pca`, `second_category`, `third_category`) de este agente.

---

## 4. Estandarización Final Acordada a Negocio (`Third`)

Por último, los modelos pueden entregar docenas de strings con categorías "crudas", pero la visualización y proyección exige una estructura resumida estándar para gerencia.

Dentro de `Third`, las tipificaciones finales se compactan usando la siguiente **tabla de equivalencias dictatorial** (`CASE category WHEN...`):

#### Prioridad de Etiquetado (Cascada de Categorización)
Si en el momento de armar el reporte el sistema principal de clasificación (PCA) no logró detectar una categoría para la conversación, el sistema aplicará automáticamente **una ley de prioridades en cascada**:
1. Intentará usar la categoría detectada por los modelos de Inteligencia Artificial de texto o voz (Post Call Analytics). Este modelo entrega el árbol completo: Categoría Nivel 1, Nivel 2 y Nivel 3.
2. Si la anterior está vacía, intentará heredar la categoría que le había asignado el Bot (Voicebot / Chatbot) si es que el cliente pasó por uno antes de hablar con el agente. **Nota:** Esta opción provee únicamente la **categoría principal (nivel 1)**; los subniveles 2 y 3 quedan sin clasificar (`NULL`).
3. Como último recurso, si ambos escenarios fallan, utilizará la categoría detectada por el **cálculo del FCR AI (inteligencia artificial de resolución al primer contacto)** que analizó esa misma interacción de chat o WhatsApp. **Nota:** Al igual que en el caso del Bot, esta opción entrega únicamente la **categoría principal (nivel 1)**.

#### Homologación
| Categoría Original detectada | Categoría Estándar para Radar |
| :--- | :--- |
| `CAMBIO_VOLUNTARIO`, `CORRECCION_NOMBRE`, `ENDOSO`, `SPLIT`, `CAMBIO_VOLUNTARIO_ERROR`, `CAMBIO_RUTA` | **`CAMBIO_VOLUNTARIO`** |
| `INFORMACION_DE_VIAJE`, `INFORMACION_DE_FRANQUICIA` | **`INFORMACION_DE_VIAJE`** |
| `VENTAS`, `PROBLEMAS_COMPRA_WEB`, `COMPROBANTE_COMPRA` | **`VENTAS`** |
| `VENTAS_ANCILLARIES`, `VENTAS y VENTAS_ANCILLARIES`, `ASIGNACION_DE_ASIENTOS` | **`VENTAS_ANCILLARIES`** |
| `SERVICIOS_ESPECIALES`, `MASCOTAS`, `MENORES_NO_ACOMPANADOS`, `VENTAS y SERVICIOS_ESPECIALES` | **`SERVICIOS_ESPECIALES`** |
| `RECLAMOS`, `RECLAMOS_EQUIPAJE`, `ESTADO_CASO`, `RECLAMO_DEVOLUCIONES` | **`RECLAMOS`** |
| `DEVOLUCIONES`, `SOLICITUD_DEVOLUCIONES` | **`DEVOLUCIONES`** |
| `CAMBIO_INVOLUNTARIO`, `Cambios Involuntarios` | **`CAMBIO_INVOLUNTARIO`** |
| `CANJE`, `UPG` | **`CANJE`** |
| `OTROS_FFP`, `OUTROS_FFP`, `ACTUALIZAR_PERFIL_CUENTA`, `FFP`, `ACREDITACION` | **`OTROS_FFP`** |
| `CHECK_IN`, `EXCEPCIONES`, `LOGIN`, `TRAVEL_VOUCHER` | *(Se mantienen iguales)* |
| `SIN INTENT`, `SIN_CONTEXTO`, `SILENCIO`, `SILENCE`, `DEFAULT`, `LATAM_WALLET`, `SILENCIO_AGENTE`, `None` | **`OTROS`** |
| Cualquier otro string no registrado... | **`NOT_CATEGORIZED`** |

De esta manera, independientemente del canal técnico que procesó al cliente, el dato que explota Radar ya viene "limpiado", "desempatado" y "homologado" a conceptos troncales del modelo de negocio.
