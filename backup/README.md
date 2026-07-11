# Backups verificados — FPTM (Fase 3.4)

Backup semanal automático de las tablas críticas de Supabase, guardado en un
**bucket privado de Supabase Storage** (`backups`), organizado por fecha.

> **Por qué no en GitHub:** este repo es público. Los exports contienen datos
> personales (emails, fechas de nacimiento, direcciones) — ni en el repo ni en
> artifacts de Actions (en repos públicos cualquiera los puede descargar).

## Activación (una sola vez)

1. Supabase → **Settings → API** → copia la **service_role key** (¡no la anon!).
2. GitHub → repo → **Settings → Secrets and variables → Actions** →
   `New repository secret`:
   - Nombre: `SUPABASE_SERVICE_ROLE_KEY`
   - Valor: la key del paso 1.
3. Corre el workflow a mano la primera vez: pestaña **Actions →
   "Backup semanal Supabase" → Run workflow**. Verifica en Supabase →
   **Storage → backups** que apareció la carpeta con la fecha de hoy.

Después corre solo, cada lunes a las 3:00 AM (hora PR).

## Correr un export local

```bash
SUPABASE_URL=https://qrvyfdpwtearfpjruwja.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=eyJ... \
node backup/export_backup.mjs          # solo local → ./backup-out/YYYY-MM-DD/
# añade BACKUP_UPLOAD=1 para subir también al bucket
```

Cada tabla se exporta en dos formatos: `.json` (fidelidad completa, es el que
usa la restauración) y `.csv` (para abrir en Excel y mirar con ojos humanos).

## El ejercicio de restauración (hazlo UNA vez)

**Backup que nunca se ha restaurado = esperanza, no backup.** El ejercicio:

1. Crea un proyecto Supabase **de prueba** (gratis) — no toques el real.
2. En el SQL Editor del proyecto de prueba, corre los scripts de esquema de
   este repo: `setup_fprtm_database.sql`, los `create_*.sql`, y
   `sql/create_audit_log.sql` + `sql/soft_delete_torneos.sql`.
3. Descarga una carpeta de backup del bucket (o usa un export local) y:

```bash
TARGET_SUPABASE_URL=https://TU-PROYECTO-PRUEBA.supabase.co \
TARGET_SERVICE_ROLE_KEY=eyJ...la-del-proyecto-prueba... \
node backup/restore_backup.mjs ./backup-out/2026-07-11
```

4. Verifica: conteos por tabla (`select count(*) from ...`) contra el
   `_resumen.txt` del backup, y abre 2-3 jugadores al azar para comparar.

Si eso funciona, tienes backups de verdad. Repite el ejercicio si algún día
cambias el esquema de forma significativa.

## Retención

Storage no borra nada solo. Con ~17 tablas pequeñas el costo es despreciable
por años; si algún día quieres limpiar, borra carpetas viejas del bucket a
mano (deja siempre al menos las últimas 8 semanas).
