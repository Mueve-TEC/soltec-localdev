# PLAN.md

# Plataforma de prueba y recolección de datos para automatización de facturas argentinas en Odoo 19 CE

> **Versión 2 (noviembre 2026).** Reescrita como *roadmap de integración*: la
> mayoría de los componentes ya existen y están avanzados. Este documento
> mapea los activos actuales, define el trabajo netamente nuevo y ordena las
> etapas hacia un piloto con equipos contables.

## 1. Objetivo

Operar una plataforma centralizada sobre **Odoo 19 Community** para probar
un flujo de automatización de facturas de proveedores argentinas y
recopilar un conjunto de datos de evaluación validado por contadores.

La plataforma permitirá:

1. Cargar facturas en PDF, imágenes, fotografías y escaneos.
2. Extraer los metadatos disponibles en el QR de ARCA.
3. Extraer los ítems de las facturas: capa de texto del PDF cuando exista
    (estrategia primaria) y modelos multimodales pequeños como fallback
    (objetivo: hasta 4B de parámetros).
4. Sugerir productos existentes en el catálogo de cada organización.
5. Sugerir cuentas contables según la configuración de cada compañía.
6. Permitir que contadores revisen, corrijan y validen las predicciones.
7. Conservar por separado el documento original, las predicciones de
    cada ejecución y el resultado validado.
8. Generar métricas y exportaciones reproducibles para comparar modelos
    y estrategias.

**Alcance inicial:** plataforma de evaluación y generación de dataset.
No se busca todavía automatizar la contabilización definitiva ni
implementar anonimización automática.

## 2. Estado actual del proyecto (avances)

Los componentes base ya existen y están en distinto grado de madurez:

  Activo                                  Repositorio / ubicación                           Estado
  --------------------------------------- ------------------------------------------------- ----------------------------------------------------------------------------------------------------------------
  Entorno Odoo 19 CE                      `soltec-localdev19-ocr/`                          Docker Compose funcional (web + db + pgadmin), imagen SolTec 19-dev, addons en `/mnt/custom-addons`.
  Localización argentina para Odoo 19     `Mueve-TEC/odoo-argentina` rama `19.0`            Stack mantenido por el equipo; provee l10n_ar completo (afipws, padron, retenciones, etc.). **No hace falta portar desde 16.**
  Módulo QR ARCA                          `odoo-argentina-invoice-ocr/l10n_ar_factura_qr`   Maduro (desarrollado en 16, migrado a 19): pyzbar + pdf2image con escalado 200→600 DPI, filtrado multi-QR por firma `?p=`, creación de borradores de facturas de proveedor, partner por CUIT, productos por proveedor, impuestos por tipo de comprobante, log de auditoría `ocr.arca.scan`.
  Módulo ítems por capa de texto          `odoo-argentina-invoice-ocr/l10n_ar_factura_items` (v19.0.1.1.0)   Puerto fiel de `TextExtractionStrategy` de `facturas-backend-UNC-PSI`; parsea tablas de ítems del texto del PDF (código, cantidad, bonificación, subtotal); fallback a línea genérica desde QR; contrato de auditoría de extracción; tests.
  Servicio de extracción VLM              `invoice-item-extractor/`                         FastAPI + Pydantic v2, endpoints `/extract`, `/models`, ciclo de vida vLLM gestionado, detección de capacidades de visión, prompt en español con catálogo fijo de impuestos (IVA 21/10.5/27/0/Exen/No Corresp, P. IIBB, percepciones), JSON Schema estricto con reintento sin esquema, normalización de números AR (`8.500,00`), CI (ruff, mypy, pytest).
  Benchmark de modelos                    `invoice-item-extractor/benchmark/`               Runner sobre datasets, P/R/F1 por ítem (matching difuso ≥0.6), exactitud por campo, impuestos como conjunto exacto, leaderboard, barridos de concurrencia y recursos, reporte HTML autocontenido.
  Datasets                                `invoice-item-extractor/eval/`                    Dataset sintéctico versionado + dataset real anotado como submódulo privado (`facturas-argentinas`) con ground truth, manifiestos y fingerprints; política de datos real definida (nunca se commitea).
  Punto de integración VLM                ADR-0004 (`docs/adr/` del OCR repo)               Define el fallback LLM en `l10n_ar_factura_items`: capa de texto primero; VLM vía API del extractor cuando falla o no hay capa de texto.
  Entorno Odoo 16 (histórico)             `soltec-localdev16-ocr/`                         Predecesor con stack 16 completo; fuente de referencia, no objetivo.
  Prototipos iniciales (históricos)       `ocr-scripts/`, `facturas-backend-UNC-PSI/`       Superseded. `ocr-scripts` consolidó las decisiones pyzbar (se descartó `qreader` por dependencias de libtorch) y PyAfipWs/padrón. `facturas-backend-UNC-PSI` aportó la estrategia de texto y el flujo Gemini/Sheets (ver riesgos).

**Trabajo netamente nuevo** (no existe todavía):

- Multi-tenencia por organizaciones con reglas de acceso y pruebas de
    aislamiento.
- Persistencia en Odoo de ejecuciones, predicciones y validaciones
    (modelo de datos de evaluación).
- Interfaz de revisión humana (pantalla de tres áreas).
- Sugerencias de productos y cuentas contables.
- Métricas operativas y de validación humana dentro de Odoo.
- Exportación de datasets validados desde Odoo.

## 3. Decisiones de diseño (cerradas)

# Decisión                                                    Resolución

  --- ----------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  1   Encuadre del plan                                          Roadmap de integración: mapear activos existentes, construir solo los faltantes.
  2   Tamaño de modelos                                          **Objetivo ≤4B** como restricción del proyecto (costo de despliegue local). Modelos mayores evaluados en el benchmark (gemma4-26b, Qwen2.5-VL-7B, Qwen3-VL-8B, GLM-OCR) se usan como **referencias/baselines**, no como objetivo.
  3   Plataforma                                                 **Odoo 19 CE + stack `Mueve-TEC/odoo-argentina` rama `19.0`** (mantenido por el equipo). Sin port manual desde 16.
  4   Estrategia de extracción de ítems                          **ADR-0004:** capa de texto del PDF primero (`l10n_ar_factura_items`); fallback a VLM vía API de `invoice-item-extractor` cuando no hay capa de texto o el parseo falla.
  5   División de la evaluación                                  Benchmark a nivel modelo (P/R/F1, leaderboards) **permanece en `invoice-item-extractor`**. Odoo calcula métricas **operativas y de validación humana** (tiempos de revisión, categorías de error, matching) sobre uso real.
  6   Ubicación del código de evaluación                          **Módulo nuevo** (`account_invoice_ai_evaluation`) para organizaciones, documentos, ejecuciones, predicciones, validaciones, UI de revisión y métricas. `l10n_ar_factura_qr` y `l10n_ar_factura_items` se mantienen como están y se conectan al nuevo módulo.
  7   Multi-tenencia en el piloto                                Reglas de aislamiento entre organizaciones se construyen y **prueban antes de incorporar equipos**; el humo de prueba inicial se hace con una sola organización; el piloto formal incorpora **2–3 equipos en paralelo, 500+ facturas reales**.
  8   Despliegue de inferencia en el piloto                      **Instancia vLLM externa con múltiples modelos** disponibles; la API del extractor sigue siendo el único punto de entrada desde Odoo.

### 3.1. Uso de documentos y confidencialidad

En la primera etapa se conservarán las facturas originales completas,
incluidas las que contengan datos comerciales o fiscales.

Antes de incorporar una organización se deberá formalizar un **acuerdo
de confidencialidad y no difusión** que establezca, como mínimo:

- Qué documentos y datos se recopilan.
- Quién puede acceder a ellos.
- Para qué se utilizarán durante la evaluación.
- Si se autoriza su uso posterior para investigación, evaluación y
    entrenamiento o ajuste de modelos.
- Cómo se conservarán, protegerán y eventualmente eliminarán los datos.
- Que no se publicarán documentos ni datos identificatorios sin
    autorización específica.

El acuerdo debe ser revisado por asesoramiento legal. La firma de un
acuerdo no reemplaza los controles técnicos de seguridad ni las
obligaciones legales aplicables.

**Autorizaciones diferenciadas.** El acuerdo no trata una autorización
única: se distinguen y registran por separado tres consentimientos:

1. **Almacenamiento y procesamiento** de documentos en la plataforma.
2. **Evaluación de modelos e investigación** sobre los datos recolectados.
3. **Entrenamiento o fine-tuning** de modelos con esos datos.

Cada nivel se otorga, registra y audita de forma independiente; la
autorización de evaluación no implica la de entrenamiento.

**La anonimización queda expresamente fuera del alcance inicial.** Se
diseñará una etapa posterior para generar copias anonimizadas destinadas
a datasets compartidos, sin modificar ni sobrescribir los originales.

## 4. Arquitectura

``` text
                Usuarios / Contadores
                         |
                         v
              +----------------------+
              |     Odoo 19 CE       |
              |                      |
              | Mueve-TEC/odoo-      |
              | argentina (l10n_ar)  |
              |                      |
              | l10n_ar_factura_qr   |  <- existe
              | l10n_ar_factura_     |
              |   items              |  <- existe (texto primero)
              | account_invoice_ai_  |
              |   evaluation         |  <- NUEVO: orgs, runs,
              |                      |     predicciones, validaciones,
              |                      |     UI revisión, métricas
              +----------+-----------+
                         |
                   API REST (ADR-0004, solo fallback VLM)
                         |
                         v
              +----------------------+
              | invoice-item-extractor|  <- existe
              | FastAPI + Pydantic   |
              | JSON Schema estricto |
              | Catálogo fijo        |
              | impuestos AR         |
              +----------+-----------+
                         |
                         v
              +----------------------+
              | vLLM externo         |  <- piloto: instancia
              | múltiples modelos    |     externa multi-modelo
              +----------------------+
```

### Responsabilidades

**Odoo 19 CE** — Interfaz de usuario. Gestión de participantes y
compañías. Gestión de documentos y adjuntos. Estados del procesamiento.
Extracción por capa de texto (nativa, en `l10n_ar_factura_items`).
Revisión y validación. Registro histórico y métricas operativas.

**invoice-item-extractor** — API de extracción VLM (`POST /extract`).
Salida JSON validada contra esquema. Registro de modelo, versión y
parámetros. Benchmark a nivel modelo. Único punto de entrada de
inferencia para Odoo.

**vLLM externo** — Sirve múltiples modelos durante el piloto. El
extractor ya soleta backends gestionados; se ajustará el ciclo de vida
para el modo externo multi-modelo.

**Almacenamiento** — PostgreSQL de Odoo para metadatos y relaciones.
`ir.attachment` para archivos. Backups cifrados y acceso restringido.

Para tareas largas: procesamiento asíncrono mediante cola de trabajos.
No ejecutar inferencias dentro de una petición HTTP interactiva de Odoo.

## 5. Flujo de procesamiento de una factura

1. **Carga:** PDF (digital o escaneado), JPG, PNG, fotografía, TIFF. Se
    conserva el original y se calcula hash (detección de duplicados).
2. **QR ARCA** (`l10n_ar_factura_qr`, existe): lectura multi-página con
    escalado de DPI, filtrado multi-QR, parseo del payload `?p=` base64,
    creación de borrador de factura de proveedor y partner por CUIT.
    Datos QR registrados como fuente independiente, con estado y errores.
3. **Ítems — capa de texto** (`l10n_ar_factura_items`, existe): si el
    PDF tiene texto seleccionable, parseo de la tabla de ítems
    (código, cantidad, bonificación, subtotal). Estrategia primaria:
    barata y exacta.
4. **Ítems — fallback VLM** (ADR-0004, a integrar): sin capa de texto o
    parseo fallido → renderizado de páginas y llamada al extractor.
    Elección de modelo configurable; se registra modelo, versión,
    prompt, parámetros y respuesta cruda.
5. **Revisión humana** (nuevo): pantalla de tres áreas — documento /
    extracción / matching. Corrección de campos, marcado de ilegibles,
    rechazo de ejecución, nueva ejecución con otro modelo.
6. **Validación:** resultado aprobado queda como ground truth,
    separado de las predicciones. Nunca se sobrescriben ejecuciones.
7. **Métricas y exportación:** comparación ejecución vs. validación;
    exportación JSONL/CSV con manifiesto versionado.

### Procedencia de cada dato

Todo dato (campo de cabecera, ítem, impuesto) debe registrar su fuente:
QR ARCA, capa de texto, VLM, o edición humana. Los datos del QR no deben
sobrescribir silenciosamente los resultados del VLM ni viceversa.

## 6. Modelo de datos del módulo de evaluación

Nombres orientativos en `account_invoice_ai_evaluation` (o el prefijo
que se ajuste a las convenciones del repo OCR):

### `account.invoice.ai.organization`

Equipo contable participante. Campos: `name`, `active`, `user_ids`,
`company_ids`, `agreement_signed`, `agreement_date`,
`agreement_version`, `data_usage_consent`, `notes`. La aceptación del
acuerdo debe ser auditable y la documentación firmada con acceso
restringido.

### Ciclo de vida de una factura

``` text
uploaded
   |
   v
processing
   |
   +----> failed
   |
   v
pending_review
   |
   v
in_review
   |
   +----> needs_correction
   |
   v
validated
```

Las ejecuciones individuales tienen su propio estado (`pending`,
`running`, `done`, `failed`, `rejected`). Una factura puede estar
validada respecto de una ejecución y tener otras ejecuciones pendientes
de revisión: el estado del documento no implica el de todas sus runs.

### `account.invoice.ai.document`

Factura cargada. Campos: `organization_id`, `company_id`,
`original_attachment_id`, `filename`, `mimetype`, `sha256`, `page_count`,
`source_type` (PDF digital / escaneado / imagen / fotografía / TIFF /
otro), `has_text_layer`, `processing_state` (ciclo de vida arriba),
`qr_state`, `qr_raw_data`, `qr_parsed_data`, `uploaded_by`,
`uploaded_at`. El hash detecta duplicados pero no es identificador único.

### `account.invoice.ai.run`

Ejecución de procesamiento; una factura tiene muchas ejecuciones.
Campos: `document_id`, `run_number`, `strategy` (`text_layer` | `vlm` |
`ocr_vlm` | `qr_only`), `pipeline_version`, `model_name`, `model_version`,
`model_quantization`, `prompt_version`, `inference_parameters`,
`raw_response`, `normalized_response`, `started_at`, `finished_at`,
`duration_ms`, `state`, `error_message`. Las ejecuciones históricas no
se sobrescriben. Las ejecuciones de capa de texto también se registran
(estrategia, versión del parser) para comparabilidad.

**Estrategia y modelo son dimensiones independientes.** El esquema debe
permitir comparar combinaciones sin acoplarse a la estrategia actual:

  Estrategia       Modelo / componente
  ---------------- --------------------
  Capa de texto    Parser v1 (`l10n_ar_factura_items`)
  VLM              Qwen2.5-VL-3B
  VLM              Gemma 4 E4B
  OCR + VLM        Pipeline experimental

### `account.invoice.ai.line`

Ítems de una ejecución. Campos: `run_id`, `sequence`, `page_number`,
`description`, `quantity`, `uom_text`, `unit_price`, `discount`,
`subtotal`, `currency_id`, `bounding_box`, `raw_item_data`.

### `account.invoice.ai.prediction`

Predicciones de matching por línea. Campos: `line_id`,
`prediction_type` (producto o cuenta), `suggested_product_id`,
`suggested_account_id`, `candidate_data`, `score`, `matching_method`,
`algorithm_version`. Las referencias deben pertenecer a la compañía
correspondiente.

### `account.invoice.ai.validation`

Validación de una **ejecución** concreta: determina si una predicción es
correcta y registra las correcciones puntuales. Campos: `document_id`,
`run_id`, `line_id`, `validated_by`, `validated_at`, `validation_state`,
`corrected_*` (descripción, cantidad, uom, precio, subtotal),
`error_categories`, `review_notes`. Conserva tanto la predicción como el
valor corregido.

### `account.invoice.ai.annotation`

Anotación de la **factura**: el resultado de referencia definitivo
(ground truth), independiente de cuántas ejecuciones exista. Una factura
con tres ejecuciones de distintos modelos tiene **una sola anotación**;
así se evita duplicar el ground truth por ejecución y cada run se compara
contra la misma referencia.

Campos: `document_id`, `line_ids`, `annotated_by`, `reviewed_by`,
`state`, `version`, `created_at`, `approved_at`. Las líneas anotadas
registran también las selecciones de matching (`selected_product_id`,
`selected_account_id`) como parte del resultado de referencia.

**Control de calidad de anotaciones.** No asumir que toda corrección de
un contador es automáticamente ground truth:

- Revisión secundaria configurable (empezar con una sola revisión;
    habilitar la segunda para casos dudosos).
- Registro de discrepancias entre contadores y su resolución.
- Identificación explícita de campos ilegibles o ambiguos.
- Historial de modificaciones de anotaciones (versionado: cada cambio
    genera una versión nueva, sin sobrescribir).

## 7. Matching de productos y cuentas contables (post-extracción)

### 7.1. Productos

Catálogo de la compañía correspondiente. Estrategia gradual: búsqueda
textual por nombre/referencia → normalización de descripciones y
unidades → embeddings si aportan mejoras → ranking de candidatos →
selección humana o automática según umbrales medidos.

Registrar: producto sugerido, lista ordenada de candidatos, puntajes y
método, producto seleccionado por el contador, y si el correcto estaba
entre los candidatos. Sin IDs de productos globales entre compañías.

### 7.2. Cuentas contables

Basadas en la configuración de la compañía: cuenta de gasto de
producto/categoría, categoría, configuración de compañía, historial
local de imputaciones validadas. Las cuentas no se comparten como
etiquetas universales entre organizaciones.

## 8. Interfaz de usuario

### 8.1. Bandeja de documentos

Vistas por estado: pendientes de procesamiento / en curso / pendientes
de revisión / validados / con errores. Filtros por organización,
compañía, proveedor, fecha, formato, estrategia (texto/VLM), modelo y
estado.

### 8.2. Pantalla de revisión (tres áreas)

1. **Documento:** PDF/imagen original, navegación de páginas, zoom.
2. **Extracción:** ítems y campos, editables; identificación clara de
    qué valores son predichos, corregidos o provienen del QR.
3. **Matching:** productos y cuentas sugeridos, candidatos alternativos,
    selección manual.

Acciones: confirmar extracción, corregir campos, marcar dato ilegible o
no identificable, marcar ítem no clasificable, rechazar ejecución,
solicitar nueva ejecución con otro modelo.

### 8.3. Roles

- **Administrador de plataforma:** participantes, configuración
    global, modelos.
- **Administrador de organización:** usuarios y compañías de su equipo.
- **Contador validador:** carga, revisa y corrige documentos de su
    organización.
- **Revisor:** verifica validaciones, resuelve casos ambiguos.
- **Investigador/evaluador:** resultados autorizados y métricas, sin
    acceso innecesario a documentos originales.

## 9. Seguridad y gobernanza de datos

Requisitos del MVP:

- Acuerdo de confidencialidad firmado antes de habilitar la carga.
- Acceso por organización y compañía; reglas de registro específicas
    para todos los modelos personalizados.
- **Pruebas automatizadas de aislamiento entre organizaciones**
    (condición de entrada del piloto multi-equipo).
- **Seguridad de adjuntos (`ir.attachment`):** proteger los registros
    no alcanza. Verificar explícitamente el acceso a los archivos,
    especialmente con `public`, `access_token`, adjuntos vinculados a
    otros modelos o URLs de descarga. Pruebas específicas (Etapa 1):
  - Acceso directo a la URL del adjunto.
  - Acceso a través del modelo de documento.
  - Descarga por otro usuario de la misma organización (permitida).
  - Descarga por usuarios de otra organización (bloqueada).
  - Acceso mediante enlaces compartidos / tokens.
- Acceso restringido a adjuntos y documentos originales.
- HTTPS obligatorio; backups protegidos y prueba de restauración.
- Registro de accesos y operaciones sensibles; gestión de bajas.
- Política documentada de conservación y eliminación.
- No enviar documentos a servicios externos no autorizados.
- Consentimiento diferenciado: evaluar modelos ≠ usar documentos en
    entrenamiento o fine-tuning.

### Issues de seguridad abiertos

- **Barrido de secretos en todos los repositorios** del proyecto antes
    de abrir el piloto (por ejemplo con gitleaks/trufflehog), incluidos
    submódulos y datasets.
- La decisión `qreader` → `pyzbar` (dependencias libtorch) ya está
    cerrada y consolidada en los módulos actuales; no reabrir.

## 10. Métricas y evaluación

### A nivel modelo — en `invoice-item-extractor` (existe)

P/R/F1 por ítem con matching difuso, exactitud por campo, impuestos como
conjunto exacto, tasa de JSON válido, tokens y latencia, leaderboard y
reportes HTML sobre datasets versionados (sintético + real privado).
Estas métricas comparan modelos y prompts **antes** del piloto.

### A nivel operación y validación humana — en Odoo (nuevo)

- Tiempo de procesamiento y de revisión por factura.
- Tiempo de inferencia por página.
- Tasa de errores por formato, proveedor o plantilla.
- Porcentaje de documentos que requieren reprocesamiento.
- Porcentaje de ítems corregidos por campo; categorías de error.
- Proporción capa de texto vs. fallback VLM (cobertura de cada
    estrategia).

### Matching

Top-1 / Top-3 accuracy de producto, Recall@k, exactitud de cuenta
contable, porcentaje sin candidato adecuado, porcentaje de decisiones
con intervención humana.

### Segmentación

Por modelo y versión, prompt y pipeline, formato de entrada, calidad del
documento, tipo de comprobante, páginas, ítems, organización (resultados
privados), proveedor (con controles anti-filtración). Evitar métricas
agregadas sobre muestras demasiado pequeñas o que permitan inferir datos
de una organización.

Tolerancias explícitas para importes numéricos: separadores decimales,
moneda y redondeo.

## 11. Exportación y versionado del dataset

Exportación solo a usuarios autorizados, respetando el alcance acordado.
Formatos: JSONL (ejemplos de extracción), CSV (métricas), archivos
asociados cuando esté autorizado. Cada ejemplo incluye identificador no
significativo, referencia a documento/ejecución, hash, formato, modelo y
versión, prompt y pipeline versionados, predicción original, resultado
validado y estado de revisión. Manifiesto con versión, fecha, filtros.
Nunca mezclar en una misma etiqueta la predicción y la corrección
humana.

Se reutilizará la política de datasets de `invoice-item-extractor/eval`
(manifiestos, fingerprints, submódulo privado para datos reales).

## 12. Organización de módulos y repositorios

``` text
odoo-argentina-invoice-ocr/            # existe (rama 19.0-dev)
├── l10n_ar_factura_qr/                # existe: QR ARCA + borradores
├── l10n_ar_factura_items/             # existe: ítems por capa de texto
│                                      # ADR-0004: punto del fallback VLM
├── docs/adr/                          # ADRs 0001-0004
└── account_invoice_ai_evaluation/     # NUEVO: orgs, documents, runs,
                                       # lines, predictions, validations,
                                       # annotations (ground truth),
                                       # UI revisión, métricas operativas,
                                       # exportaciones

Mueve-TEC/odoo-argentina (19.0)        # existe: l10n_ar completo

invoice-item-extractor/                # existe: API VLM + benchmark
├── app/                               # /extract, schemas, vLLM lifecycle
├── benchmark/                         # métricas a nivel modelo
└── eval/                              # datasets versionados

soltec-localdev19-ocr/                 # existe: entorno Compose
```

Empezar con el módulo de evaluación monolítico y extraer subcomponentes
(matching, exportación) solo cuando exista necesidad concreta.

## 13. Plan de implementación por etapas

Prioridades de desarrollo:

  Prioridad   Trabajo                                    Resultado
  ----------- ------------------------------------------ ---------------------------
  P0          Seguridad y credenciales                   Entorno habilitado
  P1          Multi-tenencia y modelos de evaluación     Núcleo de Odoo
  P2          Integración del fallback VLM               Pipeline completo
  P3          Revisión y anotación humana                Dataset confiable
  P4          Piloto con contadores                      Datos reales
  P5          Matching                                   Productos y cuentas
  P6          Métricas y exportación avanzada            Benchmark operativo
  P7          Anonimización                              Dataset compartible

### Etapa 0 — Preparación y cierre de seguridad **(bloqueante)**

- Revocar y rotar credenciales commiteadas en `facturas-backend-UNC-PSI`.
    *Bloqueante: no avanzar al piloto sin revocación completada.*
- Barrido de secretos en todos los repositorios (incl. submódulos y
    datasets).
- Definir acuerdo de confidencialidad y alcance de uso de datos.
- Instancia Odoo 19 CE con stack `odoo-argentina` 19.0 en
    `soltec-localdev19-ocr`; cargar compañías, catálogos e impuestos de
    prueba.
- Definir política de almacenamiento, backups y conservación.
- Dataset inicial: 40+ PDFs `estandar_N.pdf` + dataset real privado.

**Entregable:** entorno 19 con l10n_ar operativo y riesgos de
credenciales cerrados.

### Etapa 1 — Módulo de evaluación: núcleo

- Modelos `organization` / `document` / `run` / `line`.
- Carga de archivos, hash, detección de duplicados, estados.
- Registro de ejecuciones de capa de texto (ya existen) como runs
    trazables.
- Roles, ACL y reglas de acceso; **pruebas automatizadas de
    aislamiento entre organizaciones**.
- Pruebas de seguridad de adjuntos (`ir.attachment`): URLs directas,
    tokens, descargas cruzadas entre organizaciones (ver §9).

**Entregable:** plataforma que registra documentos y ejecuciones con
trazabilidad completa. Condición de entrada para incorporar más de una
organización.

### Etapa 2 — Fallback VLM (ADR-0004)

- Integrar `l10n_ar_factura_items` → `invoice-item-extractor /extract`.
- Cola asíncrona, reintentos, registro de modelo/versión/prompt/
    parámetros/tiempos, respuesta cruda + normalizada.
- Configuración de la instancia vLLM externa multi-modelo del piloto.
- Validar con el benchmark existente que los modelos ≤4B candidatos
    superan umbrales mínimos antes de conectarlos a Odoo.

**Entregable:** extracción de ítems reproducible con doble estrategia
(texto → VLM) y trazabilidad por ejecución.

### Etapa 3 — Validación y anotación humana

- Pantalla de revisión de tres áreas.
- Modelo `validation` (por ejecución) y modelo `annotation`
    (referencia única por factura).
- Control de calidad de anotaciones: revisión secundaria configurable,
    registro y resolución de discrepancias, campos ilegibles/ambiguos,
    versionado de modificaciones.
- Diferenciación predicción vs. anotación de referencia.
- **Exportación básica de anotaciones (JSONL)** desde esta etapa, para
    verificar temprano que los datos recolectados sirven para construir
    el dataset; los dashboards avanzados quedan para la Etapa 6.

**Entregable:** flujo de revisión que genera anotaciones confiables y
exportables.

### Etapa 4 — Piloto con contadores (single-org humo + multi-org formal)

1. **Humo (1 organización):** validar el flujo completo end-to-end con
    un equipo, corregir fricciones de UI.
2. **Piloto formal (2–3 organizaciones, 500+ facturas reales):**
    onboarding con acuerdo firmado; reglas de aislamiento ya probadas;
    métricas operativas activas desde el primer día.

**Entregable:** dataset validado por contadores + métricas operativas
reales por modelo/estrategia/formato.

### Etapa 5 — Matching

- Búsqueda textual de productos; normalización; candidatos con scores.
- Embeddings si aportan mejoras; sugerencias contables locales.
- Modelo `prediction` + registro de decisiones humanas.

**Entregable:** evaluación de matching de productos y cuentas por
compañía.

### Etapa 6 — Evaluación integral y exportación avanzada

- Dashboards de métricas operativas + matching en Odoo.
- Comparación entre modelos ≤4B usando benchmark + resultados del
    piloto.
- Exportación JSONL/CSV con manifiestos; splits de
    entrenamiento/validación/prueba.

**Entregable:** benchmark reproducible basado en documentos validados por
contadores.

### Etapa 7 — Anonimización (futura)

Detección de regiones, entidades identificatorias, redacción
irreversible, copias anonimizadas, revisión de calidad, pruebas de
filtración, publicación controlada.

## 14. Criterios de aceptación del MVP

1. Un administrador puede crear organizaciones y asociar usuarios.
2. Cada organización trabaja con varias compañías, con sus propios
    productos, impuestos y cuentas.
3. Un usuario no puede consultar documentos ni registros de otra
    organización (probado automáticamente).
4. Se cargan PDF digitales, PDF escaneados, imágenes y fotografías; el
    original permanece intacto.
5. El QR ARCA se lee, parsea y registra con errores trazables
    (`l10n_ar_factura_qr`).
6. Los ítems se extraen por capa de texto cuando existe, y por VLM
    (≤4B) en fallback, cada estrategia registrada como run.
7. Cada ejecución conserva estrategia, modelo, versión, prompt,
    parámetros y respuesta cruda.
8. Un contador corrige ítems y valida; cada factura conserva una
    **anotación de referencia única** (versionada, con control de
    calidad) y las predicciones quedan diferenciadas de ella.
9. Historial de ejecuciones por factura consultable.
10. Métricas operativas básicas calculables en Odoo; benchmark de
    modelos ejecutable en `invoice-item-extractor`.
11. Exportación de un conjunto de ejemplos autorizado, con manifiesto.
12. Backups con prueba de restauración; acceso a documentos y adjuntos
    (`ir.attachment`, URLs, tokens) restringido y probado.
13. Credenciales de `facturas-backend-UNC-PSI` revocadas y rotadas;
    barrido de secretos completado en todos los repositorios.

## 15. Riesgos y decisiones pendientes

  Riesgo o decisión                   Tratamiento propuesto
  ----------------------------------- -----------------------------------------------------------------
  Filtración entre organizaciones     Reglas de acceso, pruebas automatizadas y auditoría; obligatorio antes del piloto multi-equipo.
  Fallback VLM con modelos ≤4B por debajo del umbral   Benchmark existente define el umbral mínimo antes de conectar a Odoo; modelos mayores solo como baseline de referencia.
  Cobertura de capa de texto baja en documentos reales   Medir proporción texto vs. VLM en el piloto; el fallback VLM absorbe el gap.
  Documentos de baja calidad           Registrar calidad y permitir revisión manual.
  Respuestas inconsistentes del VLM   JSON Schema estricto + reintento (ya en extractor) + conservación de respuesta cruda.
  Cambios de modelo o prompt          Versionado obligatorio (ya en extractor; extender a Odoo).
  Etiquetas humanas incorrectas       Estados de revisión y segunda validación.
  Catálogos y cuentas diferentes      Contexto por compañía, sin IDs globales.
  Duplicados                          Hash de archivo y controles de carga.
  Costos de inferencia                Instancia vLLM externa compartida; medición por página y límites de concurrencia.
  Credenciales commiteadas (UNC-PSI)  Revocación, rotación y limpieza de historial (Etapa 0).
  Uso de datos para entrenamiento     Consentimiento específico y trazabilidad del alcance autorizado.
  Anonimización incompleta            No publicar datasets sin proceso futuro de anonimización y control.

Decisiones a cerrar durante el diseño: tamaño máximo de archivos y
páginas; formatos adicionales; política de conservación y eliminación;
almacenar imágenes renderizadas vs. regenerarlas bajo demanda; política
de doble revisión; alcance exacto de la autorización para evaluación,
investigación y entrenamiento.

## 16. Principios del proyecto

1. **Trazabilidad:** cada resultado se asocia a documento, ejecución,
    estrategia, modelo y versión.
2. **No sobrescritura:** predicciones y validaciones son registros
    separados.
3. **Aislamiento:** cada organización mantiene sus datos y contexto
    contable.
4. **Reproducibilidad:** comparaciones identifican modelos, prompts,
    parámetros y versiones.
5. **Human-in-the-loop:** las decisiones contables y los datos de
    referencia se validan por personas.
6. **Separación de responsabilidades:** Odoo gestiona el flujo; el
    extractor sirve inferencia; el l10n_ar provee la localización.
7. **Estrategia escalonada:** capa de texto primero (barata y exacta);
    VLM solo como fallback.
8. **Privacidad desde el diseño:** permisos, acuerdos y controles de
    acceso desde el MVP, aunque la anonimización sea posterior.
9. **Evolución gradual:** extracción y validación → piloto → matching
    → evaluación integral → anonimización.

## Resultado esperado

Al finalizar las primeras etapas se dispondrá de una instancia
centralizada de Odoo 19 CE con localización argentina completa, en la
que 2–3 equipos contables cargarán 500+ facturas reales, ejecutarán la
doble estrategia de extracción (texto → VLM ≤4B), revisarán y corregirán
los resultados, y generarán un historial estructurado de predicciones y
validaciones. Ese historial, junto al benchmark existente del extractor,
constituirá la base para comparar modelos, desarrollar estrategias de
matching y, en una etapa posterior, construir datasets anonimizados
destinados a investigación y entrenamiento.
