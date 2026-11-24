# PLAN_DE_CUENTAS.md — Soporte multi-plan de cuentas por tipo de organización

> Estado: plan aprobado para implementación.
> Fecha: 2026-11-19. Rama base: `19.0`. DB de referencia: `demo_ar`.
> Módulo nuevo: `account_chart_kit` (en `submodules/odoo-argentina-invoice-ocr/`).

---

## 1. Objetivo

Permitir que los estudios contables (organizaciones de la plataforma) den de alta
compañías cliente y armen fácilmente el plan de cuentas de cada una según su
**tipo de organización** (forma legal + rubro), reutilizando al máximo los
mecanismos nativos de Odoo 19 y la localización `l10n_ar`.

## 2. Decisiones tomadas

| Tema                                                                                       | Decisión                                                                                                              |
| ------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| Significado de "tipo de organización"                                                      | **Forma legal + rubro** (SA, SRL, cooperativa, ONG… × comercio, servicios, industria, agro…)                          |
| Divergencia del plan                                                                       | **Base común + extras**: chart nativo de `l10n_ar` según responsabilidad ARCA + "paquetes de cuentas" (kits) por tipo |
| Mantenimiento de paquetes                                                                  | **Contadores vía UI** (modelo almacenado, editable/clonable; no data files)                                           |
| Alcance v1                                                                                 | **Alta de cliente end-to-end**: wizard que crea la compañía con chart correcto + kits aplicados + vínculo al estudio  |
| Retrofit de compañías con asientos                                                         | Fuera de alcance (Odoo no soporta cambiar chart con movimientos)                                                      |
| `account_chart_update` (OCA)                                                               | **Diferido** — se evalúa post-v1 como herramienta de mantenimiento tras upgrades de imagen                            |
| Nota de dirección Odoo 19.1/20 (`company_type` eliminado, `is_company` computado por l10n) | **Diferida** — sin impacto para 19.0                                                                                  |

## 3. Contexto técnico verificado (imagen `soltec-localdev-odoo19:1.0`, Odoo 19)

### 3.1 Situación actual del código propio

- El estudio contable se modela con `account.invoice.ai.organization`
  (`account_invoice_ai_evaluation/models/ai_organization.py`) y el vínculo con las
  compañías cliente es `res.company.ai_organization_id` (M2O) +
  `res.users.ai_organization_ids` (M2M). Aislamiento por record rules
  `security/ai_evaluation_rules.xml` (dominio org + company).
- No existe ningún módulo propio de charts: las compañías usan el chart que
  instala `l10n_ar` (hoy `ar_ri` en `demo_ar`).
- No existe ningún campo de forma legal/rubro del cliente.
- Pipeline OCR/AI — puntos de contacto con el plan de cuentas (no modificar su
  comportamiento):
  - `l10n_ar_factura_qr/models/ocr_arca_scan.py:609` `_get_line_account_id`:
    producto (cuenta de gasto) → default del journal → payable del partner.
  - `ocr_arca_scan.py:445` `_get_tax_for_invoice_type`: heurísticas por
    nombre/grupo AFIP ("IVA No Corresp", etc.) — **asume nomenclatura del chart
    AR**, por eso los kits solo agregan cuentas y no tocan impuestos.
  - `account_invoice_ai_evaluation/services/matching.py:89-97`
    `expense_account_for_product` (scope por company).
  - `account_invoice_ai_platform/models/ai_annotation.py:611-648`
    `_prepare_bill_line` y `:650-699` `_create_or_update_bill` (vendor bill).
  - Constraints company↔cuenta: `ai_annotation.py:351-369`, `ai_prediction.py:43-61`
    (usan `account.account.company_ids`).

### 3.2 Mecanismos nativos que se reusan (verificados en la imagen)

| Mecanismo                                                                                                                                         | Ubicación                                                                                                                                                                    | Reuso                                                                                                            |
| ------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Charts AR como templates CSV (`ar_ri`, `ar_ex`, `ar_base` + impuestos, grupos, posiciones fiscales con códigos AFIP)                              | `l10n_ar/data/template/`                                                                                                                                                     | Base de todo: los kits agregan cuentas **sobre** el chart instalado                                              |
| Mapeo responsabilidad ARCA → chart (`res_RM→ar_base`, `res_IVAE→ar_ex`, `res_IVARI→ar_ri`)                                                        | override de `try_loading` en `l10n_ar/models/account_chart_template.py:53-61`                                                                                                | El wizard setea país+responsabilidad y deja que este override elija el chart. **El wizard no mapea nada propio** |
| Selección de chart por compañía                                                                                                                   | `res.company.chart_template` (Selection, `account/models/company.py:117`)                                                                                                    | Tal cual; UI nativa para cambiar chart de una compañía sin asientos                                              |
| Carga de chart al crear compañía / instalar localización                                                                                          | `account/models/company.py:484-494` (create con padre con chart → `_load` del chart del padre vía precommit) y `:968-991` (`install_l10n_modules` → `try_loading` con remap) | Punto de entrada nativo que llama el wizard                                                                      |
| Guard de asientos existentes                                                                                                                      | `res.company._existing_accounting` (`account/models/company.py:995`)                                                                                                         | Advertencias del wizard "Aplicar paquete"                                                                        |
| Defaults por compañía (`journal.default_account_id`, `product.category.property_account_expense_categ_id`, `partner.property_account_payable_id`) | core `account`                                                                                                                                                               | El pipeline OCR ya los usa; los kits pueden setearlos (opcional fase 3)                                          |

Nuance importante de jerarquía: el auto-load del padre usa `_load` (no
`try_loading`), por lo que **no pasa por el remap de responsabilidad**. Un cliente
monotributista creado como hija de una raíz con `ar_ri` recibiría `ar_ri` sin
remap. Por eso el wizard carga el chart de forma explícita y determinista
(§ 7.3 y § 11.1).

### 3.3 Búsqueda de módulos existentes (OCA / ingadhoc) — conclusión

Verificados: OCA/account-financial-tools 19.0 (18 módulos), OCA/multi-company
19.0, OCA/l10n-argentina 19.0, ingadhoc/odoo-argentina 19.0 y `l10n_ar_partner`
(títulos de personería, 12.0, sin rama 19).

- **No existe ningún módulo** que implemente paquetes de cuentas por tipo de
  organización mantenibles por UI, taxonomía de forma legal/rubro en compañías,
  ni wizard de alta de cliente guiado → el módulo nuevo cubre un gap real.
- `account_chart_update` (OCA, 19.0.1.2.1) existe y sirve para sincronizar charts
  tras upgrades de template — **diferido** (§ 12).
- `l10n_ar_partner` valida como antecedente los nombres de la taxonomía
  ("títulos de personería") pero no es reutilizable.

## 4. Approach

**Chart nativo por responsabilidad (mecanismo Odoo 19) + kits de cuentas
(UI-mantenibles, recomendados por forma legal/rubro) + wizard de alta de
cliente end-to-end.**

Por qué no charts propios por tipo: los templates de Odoo 19 son CSVs de módulo
(no records ORM); un chart por tipo duplicaría impuestos/posiciones fiscales/
códigos AFIP N veces, rompería las heurísticas de impuestos del OCR y su
mantenimiento sería inviable. Los kits solo **agregan** cuentas/grupos → el
pipeline queda intacto y la decisión de chart sigue siendo la nativa (al alta del
cliente, que es el único momento soportado).

## 5. Módulo nuevo: `account_chart_kit`

Ubicación de las fuentes (única zona editable):
`submodules/odoo-argentina-invoice-ocr/account_chart_kit/` — se sincroniza a
`custom-addons/` con `bash copy_addons.sh` (o `make sync`).

Depends: `account`, `l10n_ar`, `account_invoice_ai_platform`
(la referencia a `account.invoice.ai.organization` viene de evaluation; platform
para integración de menú/wizard en la app contable).

Estructura:

```
account_chart_kit/
├── __init__.py
├── __manifest__.py
├── models/
│   ├── __init__.py
│   ├── account_chart_kit_tag.py
│   ├── account_chart_kit.py
│   ├── account_chart_kit_line.py
│   └── res_company.py
├── wizard/
│   ├── __init__.py
│   ├── account_chart_kit_apply.py      # "Aplicar paquete" a compañía existente
│   └── account_client_setup.py         # Alta de cliente end-to-end
├── security/
│   ├── account_chart_kit_security.xml  # grupo + reglas
│   └── ir.model.access.csv
├── views/
│   ├── account_chart_kit_views.xml     # kit: form/list/search
│   ├── account_chart_kit_tag_views.xml
│   ├── res_company_views.xml          # herencia form compañía
│   ├── account_chart_kit_apply_views.xml
│   └── account_client_setup_views.xml
├── data/
│   ├── account_chart_kit_tag_data.xml  # taxonomía semilla
│   └── account_chart_kit_data.xml      # kits de ejemplo
├── i18n/
│   └── es_AR.po
└── tests/
    ├── __init__.py
    ├── test_account_chart_kit.py
    └── test_account_client_setup.py
```

### 5.1 `account.chart.kit.tag` (taxonomía UI-extensible)

- `name` (required), `tag_type` Selection: `legal_form` | `activity`, `active`.
- Seed (§ 6): ~8 formas legales + ~8 rubros. Los contadores pueden crear valores
  nuevos desde la UI sin código.

### 5.2 `account.chart.kit` ("Paquete de cuentas")

- `name`, `active`, `description`.
- `legal_form_ids` / `activity_ids` M2M a tags → definen a qué tipos se
  **recomienda** el kit (matching en el wizard).
- `line_ids` O2M `account.chart.kit.line`.
- Cross-company por diseño: los kits **no** referencian records de cuentas
  (en Odoo 19 no hay template-records ORM); se materializan en cada compañía al
  aplicarse.

### 5.3 `account.chart.kit.line`

- `kit_id`, `sequence`.
- `code`, `name`, `account_type` (Selection estándar de `account.account`),
  `reconcile`.
- `group_code` + `group_name` (char, opcionales): se crea el `account.group`
  faltante en la compañía destino; si vienen vacíos se deriva del prefijo del
  código (mismo criterio jerárquico del chart AR).

### 5.4 Herencia de `res.company`

- `legal_form_id`, `industry_id` M2O a `account.chart.kit.tag`
  (dominio por `tag_type`; naming final a confirmar al implementar para evitar
  colisiones con fields estándar).
- `applied_kit_ids` M2M a `account.chart.kit` (auditabilidad de qué se aplicó).
- Compute no almacenado `recommended_kit_ids` (kits cuyo
  legal_form/activity matchean los tags de la compañía).

### 5.5 Motor de aplicación: `account.chart.kit._apply(company)`

- Por línea: si no existe `account.account` con ese `code` en la compañía →
  crearla; primero asegurar el `account.group` (por `group_code`, creándolo si
  falta). Idempotente: re-aplicar no duplica.
- Registrar en `company.applied_kit_ids` y postear resumen en el chatter de la
  compañía (cuentas creadas / skipeadas).
- Ejecutado con `sudo()` acotado desde los wizards (§ 7.1).
- Constraint suave (warning, no bloqueo) si se aplica un kit no recomendado
  para el tipo de la compañía.

### 5.6 Wizard "Aplicar paquete" (`account.chart.kit.apply`)

Para compañías **ya existentes**: seleccionar compañía (por default la del
contexto) + kits (recomendados pre-tildados según tags, resto seleccionable) →
preview (cuentas a crear / skipeadas) → aplicar. Usa
`_existing_accounting` para advertir si la compañía tiene asientos (los kits no
tocan cuentas usadas; el warning es informativo).

### 5.7 Wizard "Alta de cliente" (`account.client.setup`) — v1 core

Form por pasos:

1. **Cliente**: estudio contable (filtrado a
   `user.ai_organization_ids`), nombre, CUIT, responsabilidad ARCA,
   forma legal, rubro.
2. **Plan**: muestra el chart que instalará Odoo (derivado de la responsabilidad,
   vía el remap nativo) + kits recomendados pre-tildados según forma legal+rubro
   - selector para agregar otros.
3. **Aplicar** (orden determinista, § 11.1):
   1. Crear `res.company` con país AR, moneda ARS, VAT, responsabilidad,
      `ai_organization_id` — **sin** `chart_template` en los vals.
   2. `account.chart.template.try_loading(code, company)` → el override de
      `l10n_ar` remapea por responsabilidad ARCA.
   3. Aplicar kits seleccionados (motor § 5.5).
   4. Agregar la compañía a `company_ids` del usuario creador y (opcional,
      checkbox) a los demás usuarios del estudio elegido.
   5. Pantalla de resumen (compañía, chart cargado, cuentas creadas por kit).

## 6. Datos semilla (data/)

- Taxonomía: formas legales (SA, SRL, SAS, SAU, Cooperativa, Asociación civil,
  Fundación, Unipersonal) + rubros (Comercio, Servicios, Industria,
  Agropecuario, Profesional, Construcción, Tecnología, Otros).
- 3 kits de ejemplo (patrón para que los contadores clonen/editen):
  - "ONG / Asociación civil — Fondos restringidos" (fondos específicos,
    resultados acumulados por fondo).
  - "Cooperativa — Aportes y fondo de reserva" (capital social, fondo de
    reserva legal, participaciones).
  - "SA — Capital suscripto/integrado" (cuentas de capital 2.x).

## 7. Seguridad

1. **`sudo()` acotado**: crear `res.company` y cargar charts es privilegio
   admin-only en Odoo. Ambos wizards validan que el estudio elegido pertenezca a
   `user.ai_organization_ids` y luego usan `sudo()` **solo** para
   create de compañía + `try_loading` + aplicación de kits. Revisar esta parte
   con el skill `odoo-security` al implementar.
2. Grupo nuevo `account_chart_kit.group_kit_manager` ("Gestor de paquetes
   contables"): create/write/unlink de kits, líneas y tags. Asignado a org
   admins / platform managers. Lectura de kits: usuarios contables.
3. ACLs (`ir.model.access.csv`) para kit/tag/line + wizards; record rules
   siguiendo el patrón de `security/ai_evaluation_rules.xml` donde aplique.
4. Aislamiento multi-org: el wizard solo agrega la nueva compañía a los
   `company_ids` de los usuarios del estudio elegido — nunca de otros estudios.
5. Los kits son un **template compartido** (no dato sensible de cliente):
   globales con acceso por grupo. Kits por-estudio con clonado queda como
   extensión futura (§ 12).

## 8. Integración con el pipeline OCR/AI existente

- Los kits **no tocan impuestos** → las heurísticas de
  `_get_tax_for_invoice_type` siguen encontrando "IVA No Corresp", etc.
- Las cuentas nuevas respetan `company_id` → los constraints de
  `ai_annotation.py:351` / `ai_prediction.py:43` siguen validando.
- Opcional fase 3 (no bloquea v1): kit line tipo "default" para setear
  `journal.default_account_id` del journal de compras o
  `product.category.property_account_expense_categ_id` → mejora el matching
  automático de `_get_line_account_id` (producto → journal → partner).

## 9. Fases de implementación

### Fase 1 — Core

- [ ] `models/` completos (tag, kit, line, res.company) + `_apply`.
- [ ] `security/` (grupo + ACLs).
- [ ] `data/` semilla (taxonomía + 3 kits).
- [ ] Tests `test_account_chart_kit.py` (TransactionCase):
      idempotencia del apply, creación de grupos, kits recomendados por tags,
      constraint de warnings, cuentas quedan en la compañía correcta.

### Fase 2 — UI de kits y compañía

- [ ] Vistas kit/tag (form con líneas editables, list, search con filtros por
      forma legal/rubro) + menú en Configuración de la app contable.
- [ ] Herencia del form de `res.company`: grupo "Tipo de organización"
      (forma legal, rubro, kits aplicados read-only).
- [ ] Wizard "Aplicar paquete" + vista + tests.

### Fase 3 — Alta de cliente end-to-end

- [ ] Wizard `account.client.setup` (3 pasos, § 5.7) + action "Nuevo cliente"
      en la app contable (visible para org admins).
- [ ] Tests end-to-end: compañía creada → chart correcto por responsabilidad
      (incl. caso monotributista → `ar_base`) → kits aplicados → vínculo
      `ai_organization_id` → compañía visible para usuarios del estudio (y no para
      los de otros estudios).
- [ ] Validación manual en `demo_ar` como `org_admin_a`.

Por fase, workflow obligatorio (AGENTS.md):
editar solo en `submodules/odoo-argentina-invoice-ocr/account_chart_kit/` →
`make sync` → `make restart` (o `make up`) →
`make upgrade DB=demo_ar MODULE=account_chart_kit` → tests (§ 10).
Commits: primero dentro del submódulo, luego bump del gitlink acá
(solo cuando se pida explícitamente).

## 10. Verificación y comandos

```bash
make sync                                                   # submodules/ -> custom-addons/
make upgrade DB=demo_ar MODULE=account_chart_kit            # vistas/data/security
make test DB=demo_ar MODULE=account_chart_kit               # -u + --test-enable (filtrado)
make test DB=demo_ar MODULE=account_chart_kit TEST_TAGS=/account_chart_kit
ruff check custom-addons/account_chart_kit                  # lint del módulo (gitignored -> ruff directo)
```

- Traducciones: terms en inglés + `i18n/es_AR.po`; al cambiar .po →
  `-u account_chart_kit --i18n-overwrite` (recordar: sin overwrite no reemplaza
  términos existentes y msgstr vacíos se ignoran).
- Al terminar: `make lint` (supermodule) + revisión manual del wizard en la UI
  con hard-refresh (caches de traducciones).

## 11. Riesgos y notas técnicas

1. **Carga determinista del chart** (crítico, fase 3): crear la compañía **sin**
   `chart_template` en los vals y con país/responsabilidad ya seteados, y llamar
   `try_loading` explícitamente en el paso 2 — el override de `l10n_ar` remapea
   por responsabilidad. Evitar el path del auto-load del padre
   (`account/models/company.py:491` usa `_load` sin remap): si la jerarquía de
   compañías del estudio tiene raíz con chart, el wizard debe controlar el orden
   (crear → `try_loading` → kits) antes del precommit. Patrón validado por la
   experiencia de la comunidad: país primero, chart en paso separado.
2. **`sudo()` acotado** en creación de compañía: revisar con `odoo-security`;
   validar membresía de estudio antes de elevar privilegios.
3. **Naming** de campos heredados (`legal_form_id`, `industry_id`): confirmar
   no-colisión con fields estándar/enterprise al implementar.
4. **Tests con carga de chart**: cargar `ar_ri` vía `try_loading` en el setup
   del test es lento; preferir un setUpClass compartido por clase de test.
5. **Idempotencia**: el motor busca por `(company_id, code)` antes de crear;
   re-aplicar un kit nunca duplica ni falla.
6. **Multi-compañía en wizard**: `allowed_company_ids`/`sel_company_ids` — el
   wizard opera en la compañía nueva vía `sudo()` + `with_company()` para la
   creación de cuentas.

## 12. Fuera de alcance / diferido

- `account_chart_update` (OCA) como submódulo para mantenimiento post-upgrade
  de charts de clientes existentes. Reevaluar post-v1; decisión pendiente:
  submodulo del repo OCA completo (arrastra ~18 módulos inertes al addons path)
  vs vendor/fork del módulo solo.
- Cambiar/retrofit del chart de compañías con asientos ya cargados.
- Kits por-estudio (clonado/versionado) y edición avanzada de kits si los
  contadores lo piden.
- Migración del concepto a Odoo 20 (`company_type` eliminado de base,
  `is_company` computado por localización — PR odoo/odoo#211043): reevaluar
  cuando se rebace de versión.
