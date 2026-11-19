# Kileaaa → ratings.ttmpr.xyz | import gate v1 (offline)

**Estado: preintegración, sólo rama de revisión.** No exponer endpoint de importación, habilitar carga de CSV, escribir PostgreSQL ni cambiar roles/políticas RLS.

## Separación de responsabilidades

- **Kileaaa:** administrar torneos, inscripciones, grupos, llaves, resultados, certificación de Mesa Técnica y exportar un JSON de sólo resultados.
- **ratings.ttmpr.xyz:** resolver identidad de cada Member ID contra el padrón canónico, calcular diferencias usando **su propio código** de index.html (getPoints y POINT_TABLE), aprobar, aplicar, auditar y publicar los ratings oficiales.
- **Kileaaa** recuperará únicamente el rating oficial publicado y un recibo de estado (API de lectura aún pendiente).

## Qué implementa este PR

El módulo integrations/kileaaa/certified-results.mjs exporta **sólo funciones puras**, sin red, credenciales, SQL ni escritura:

1. **validateKileaaaCertifiedResults(raw)**: valida esquema exacto kileaaa-certified-results-v1, tamaño, fecha, torneo oficial, identidades, sets, BYE, dobles, Default, W/O, retiro, orden, unicidad y SHA-256; devuelve paquete inmutable con importStatus = validation_only y publicationAuthorized = false.
2. **previewKileaaaRatingChanges(validated, officialRoster, officialGetPoints)**: requiere snapshot del padrón suministrado por FPTM; usa la **función oficial existente** getPoints() inyectada. Calcula simulación del lote con rating congelado para comparación, no escribe. Se excluyen BYE/W/O/retirados/dobles; Default puntúa conforme al algoritmo existente.
3. **assessKileaaaReplay(validated, priorReceipt)**: clasificación **sin cambios de base** de paquete nuevo, repetido o versión que requiere revisión manual. No sustituye una restricción de unicidad SQL.

Las pruebas tests/kileaaa-certified-results.test.mjs comprueban contrato y proyección contra la función real que el arnés de Fase 0 extrae de index.html.

### Pruebas locales

    node --test tests/*.test.mjs

Usar Node 22 o posterior. No hacen falta paquetes externos.

## Advertencias de seguridad obligatorias

- **SHA-256 no autentica al remitente.** Cualquiera puede cambiar JSON y calcular nueva huella. Un futuro endpoint debe obtener el documento de Kileaaa por canal autenticado de servidor a servidor y verificar que el cierre está aprobado y vigente. No aceptar uploads públicos ni asumir que el archivo por sí mismo demuestra certificación.
- **Bloqueantes de la auditoría existente:** SECURITY_FINDINGS.md F-01 (cualquier autenticado parece admin), F-02 (tabla base contiene datos expuestos), F-03 (escrituras directas desde browser), F-04 (RLS demasiado permisiva), F-06 y F-10 (atribución y staging). **No integrar en producción antes de resolverlos y auditar.**
- La API pública api_jugadores sirve para **visualización**, no se debe asumir que su rating es un snapshot transaccional. El cálculo de importación requiere lectura canónica protegida y un nuevo bloqueo de filas al publicar.
- Un paquete v1 puede tener date: null en Kileaaa si el torneo es antiguo; el nuevo importador lo rechaza hasta revisión/corrección de fecha en origen.
- El contrato identifica dobles con cuatro Member IDs. Si los dobles exportados no incluyen ambas parejas, el importador los rechaza (no hace inferencias).
- Las clasificaciones played, default, walkover, retired, doubles y bye son datos de origen, pero la autorización oficial debe además comprobar que torneo y cada partido están realmente certificados.
- Toda revisión posterior de resultados debe crear un flujo explícito de corrección con trazabilidad. Nunca sobrescribir silenciosamente un torneo publicado.
- Datos de pruebas: **ficticios exclusivamente**. No registrar datos reales, emails, fechas de nacimiento, direcciones ni credenciales.

## Etapas todavía pendientes

1. Restaurar un backup *anonimizado* en staging y validar DDL, permisos y aislamiento; no dar permisos amplios a Kileaaa.
2. Construir endpoint FPTM de carga **autorizado**, sólo después del hardening. Verificar fuente y estado de cierre mediante autenticación y firma/canal seguro.
3. Revalidar snapshot del padrón oficial, bloquear filas relevantes, calcular con getPoints() y mostrar diferencias a operador autorizado.
4. Aprobar de forma **independiente**, aplicar atómicamente ratings/partidos/resultados/recibo con restricción única por torneo fuente y huella, auditoría de actor y fecha y rollback de errores.
5. Exponer estado/recibo de lectura a Kileaaa; mantener compatibilidad con históricos y proteger esquema privado.
6. Ensayos de duplicados, concurrencia, cambios de baseline, Default/W/O, faltantes, límites, alteraciones, recuperación y restauración; aprobación humana antes de conectar producción.

## No confundir con el CSV de Stadium

El JSON kileaaa-certified-results-v1 **no es un CSV de Stadium Compete**. No debe subirse a la herramienta CSV histórica ni reinterpretarse por columnas del CSV sin un adaptador validado.

**No-Go:** este PR no hace deploy, no crea ruta en index.html, no crea secretos y no modifica Supabase, membresías, rating histórico ni políticas RLS.
