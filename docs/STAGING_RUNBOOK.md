# Runbook — crear Kileaaa Staging

Pasos manuales, para ejecutar una persona en el panel de Supabase.
Complementa `docs/PHASE0_BACKUP_AND_STAGING.md` (que explica el *porqué*);
esto es el *cómo*, en orden.

> **Nada de este runbook se ha ejecutado.** No se ha creado ningún proyecto.

## Regla que no se rompe

**Producción y staging nunca comparten datos escribibles.** Proyectos
distintos, credenciales distintas, flujo en un solo sentido
(producción → staging). Ninguna credencial de uno se configura jamás en el
otro.

---

## Paso 0 · Extracción del esquema (BLOQUEA TODO LO DEMÁS)

Cinco tablas núcleo no tienen DDL en el repositorio. Sin ellas no hay
staging. Hay que sacarlas de producción, **sólo esquema, sin filas**.

### Opción A — Supabase CLI (recomendada)

En tu máquina, no en un contenedor efímero:

```bash
npx supabase login
npx supabase link --project-ref qrvyfdpwtearfpjruwja
npx supabase db dump --schema public --data-only=false -f produccion_schema.sql
```

`db dump` sin `--data-only` emite **sólo DDL**. Verifica antes de seguir:

```bash
grep -c "^INSERT INTO\|^COPY " produccion_schema.sql   # debe dar 0
```

Si da algo distinto de 0, **para**: el fichero lleva datos y no debe entrar
al repositorio.

### Opción B — pg_dump directo

Necesitas la cadena de conexión (Supabase → Settings → Database).

```bash
pg_dump "postgresql://postgres:<PASSWORD>@db.<ref>.supabase.co:5432/postgres" \
  --schema-only --schema=public --no-owner --no-privileges \
  -f produccion_schema.sql
```

⚠️ La contraseña va en la línea de comandos: quedará en tu historial de
shell. Bórralo después (`history -d`), o usa `PGPASSWORD` en una variable de
entorno de un solo uso.

### Opción C — sin CLI, desde el editor SQL

Si no puedes instalar nada, saca al menos las definiciones que faltan
ejecutando esto en Supabase → SQL Editor y copiando el resultado:

```sql
-- Columnas de las tablas núcleo
SELECT table_name, ordinal_position, column_name, data_type,
       character_maximum_length, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('Base de Datos','torneos','partidos',
                     'resultados_evento','jugadores')
ORDER BY table_name, ordinal_position;

-- Claves primarias, únicas y foráneas
SELECT tc.table_name, tc.constraint_type, tc.constraint_name,
       kcu.column_name, ccu.table_name AS referencia, ccu.column_name AS ref_col
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu
       ON kcu.constraint_name = tc.constraint_name
LEFT JOIN information_schema.constraint_column_usage ccu
       ON ccu.constraint_name = tc.constraint_name
WHERE tc.table_schema = 'public'
ORDER BY tc.table_name, tc.constraint_type;

-- Índices
SELECT tablename, indexname, indexdef FROM pg_indexes
WHERE schemaname = 'public' ORDER BY tablename, indexname;

-- Políticas RLS (todas, para comparar con 090)
SELECT tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies WHERE schemaname = 'public' ORDER BY tablename, policyname;

-- Estado de RLS por tabla
SELECT relname, relrowsecurity FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r' ORDER BY relname;

-- Vistas y funciones que faltan en el repositorio
SELECT table_name, view_definition FROM information_schema.views
WHERE table_schema = 'public' AND table_name = 'miembros_alertas';

SELECT routine_name, routine_definition FROM information_schema.routines
WHERE routine_schema = 'public' AND routine_name = 'update_updated_at';

-- ¿jugadores tiene filas o es un residuo?
SELECT count(*) FROM public.jugadores;

-- Buckets de Storage
SELECT id, name, public FROM storage.buckets;
```

### Qué NO exportar, en ninguna opción

- Filas de cualquier tabla
- El esquema `auth` ni `auth.users`
- Objetos de Storage (los ficheros)
- Secretos o credenciales

### Al terminar

1. Repasa el fichero a ojo: no debe contener datos personales.
2. Escribe el DDL de las cinco tablas núcleo en
   `sql/schema/010_core_tables.sql` y **borra**
   `sql/schema/010_core_tables.PENDING.sql`.
3. Añade las políticas de `SELECT` que faltan a
   `sql/schema/090_rls_current_snapshot.sql` — **tal cual están**, sin
   corregirlas.
4. Compara el resto del volcado con `docs/SCHEMA_MANIFEST.md` y anota
   cualquier diferencia.

---

## Paso 1 · Crear el proyecto

Supabase → **New project**.

| Campo | Valor |
|---|---|
| Nombre | `kileaaa-staging` |
| Organización | la misma que producción |
| Región | **la misma que producción**, para que las latencias se parezcan |
| Plan | Free es suficiente hasta la Fase 2 |
| Contraseña de BD | **nueva, distinta de producción**, guardada en el gestor de contraseñas |

Anota el `project ref` — lo necesitarás luego.

---

## Paso 2 · Separación de credenciales

De Settings → API, guarda por separado y **nunca en el repositorio**:

| Credencial | Dónde va |
|---|---|
| URL de staging | Gestor de contraseñas, entrada "Kileaaa Staging" |
| Llave publicable de staging | Ídem |
| `service_role` de staging | Ídem, marcada como secreto |

Convención de nombres, para que no se puedan confundir en un script:

| Entorno | Variable |
|---|---|
| Producción | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` |
| Staging | `STAGING_SUPABASE_URL`, `STAGING_SERVICE_ROLE_KEY` |

Si algún día añades la `service_role` de staging a los secretos de GitHub,
usa `STAGING_SERVICE_ROLE_KEY`. **No reutilices el nombre de producción**: el
workflow de backup lee `SUPABASE_SERVICE_ROLE_KEY` y apuntaría al sitio
equivocado.

---

## Paso 3 · Extensiones

Database → Extensions → habilitar **`pg_cron`**.

Hazlo antes del esquema: `070_functions_triggers.sql` programa el job de
purga y falla si el esquema `cron` no existe.

---

## Paso 4 · Aplicar el esquema

SQL Editor, en orden numérico estricto. Uno por uno, comprobando que cada
uno termina sin error antes de pasar al siguiente:

```
000_extensions.sql
010_core_tables.sql          ← el que escribiste en el Paso 0
020_core_alterations.sql
030_registration.sql
040_content.sql
050_membership.sql
060_copa_olimpica.sql
070_functions_triggers.sql
080_views.sql
090_rls_current_snapshot.sql
100_storage.sql
```

Todos son idempotentes: si uno falla a medias, se puede volver a lanzar
entero tras corregir.

> Si `010` sigue siendo el fichero `PENDING`, el primer intento lanzará un
> `RAISE EXCEPTION` a propósito. Es la guarda: significa que falta el Paso 0.

---

## Paso 5 · Storage

`100_storage.sql` crea `club-logos` y sus políticas.

**`player-photos` hay que crearlo a mano** — ningún fichero del repositorio
lo define. Storage → New bucket:

- Nombre: `player-photos`
- Público: sí (así está en producción)
- Políticas: replicar las de producción, que hay que consultar antes en
  Storage → Policies del proyecto real

No crees el bucket `backups` en staging: no hay nada que respaldar todavía.

---

## Paso 6 · Auth

Authentication → Providers → **Email** habilitado, el resto deshabilitados.

Crea la cuenta de administración de prueba:

- Authentication → Users → **Add user**
- Correo: uno que controles y que **no** sea el de producción, p. ej.
  `admin@staging.invalid` o un alias tuyo con `+staging`
- Marca el correo como confirmado a mano (staging no envía correo)

⚠️ Las políticas RLS de `090` comprueban literalmente
`auth.jwt() ->> 'email' = 'joel@ttmpr.xyz'` (hallazgo F-05). Con otro correo,
esa cuenta **no** será admin en staging. Dos opciones:

- **Recomendada:** crea el usuario de staging con el mismo correo que
  producción. Es un proyecto distinto, así que no hay cruce de credenciales,
  y staging reproduce producción con exactitud.
- Alternativa: edita el correo en las políticas de tu copia de `090`. Rompe
  la equivalencia con producción — anótalo si lo haces.

**No** copies usuarios de `auth.users` de producción.

### Desactivar envíos y cobros reales

- Authentication → Emails: deja las plantillas por defecto y **no**
  configures SMTP propio. Sin SMTP, Supabase no manda correo a direcciones
  reales.
- No configures ninguna credencial de ATH Móvil ni de Stripe en staging. Si
  alguna vez hacen falta, sólo claves de *test*, nunca las de producción.

---

## Paso 7 · Configurar la aplicación

Todavía no existe el Developer Mode (es Fase 1.5), así que de momento:

1. Copia local de `index.html`.
2. Sustituye `SUPABASE_URL` y `SUPABASE_KEY` por los de staging.
3. **No** commitees esa copia.

### Banner permanente de staging

Obligatorio: sin él, alguien acabará creyendo que mira producción. Añade a la
copia local, justo después de `<body>`:

```html
<div style="position:fixed;top:0;left:0;right:0;z-index:99999;
            background:#b4531f;color:#fff;text-align:center;
            font:700 12px/28px system-ui,sans-serif;letter-spacing:.08em;
            text-transform:uppercase;pointer-events:none;">
  ⚠ STAGING — datos de prueba — no es producción
</div>
<style>body{padding-top:28px}</style>
```

Cuando llegue el Developer Mode, el banner pasa a pintarlo él, con color por
entorno (rojo para producción).

---

## Paso 8 · Datos

Sólo cuando exista el script de anonimización (Fase 1.1). Nunca antes:
restaurar un backup sin anonimizar mete datos personales reales en un
entorno menos protegido.

```bash
STAGING_SUPABASE_URL=https://<ref>.supabase.co \
STAGING_SERVICE_ROLE_KEY=<service_role de staging> \
node backup/restore_backup.mjs ./backup-anonimizado/<fecha>
```

> `restore_backup.mjs` lee hoy `TARGET_SUPABASE_URL` / `TARGET_SERVICE_ROLE_KEY`.
> Adaptar los nombres, o exportar ambos, es parte de la Fase 1.1.

Qué se copia y qué se anonimiza: `docs/PHASE0_BACKUP_AND_STAGING.md`, Parte 3.

---

## Verificación

Marca cada punto antes de dar staging por bueno:

- [ ] `010_core_tables.sql` existe y `010_core_tables.PENDING.sql` ya no
- [ ] El volcado no contenía ni un `INSERT` ni un `COPY`
- [ ] Los 11 ficheros de `sql/schema/` se aplicaron sin error
- [ ] `select count(*) from information_schema.tables where table_schema='public'` = 20
- [ ] `select count(*) from information_schema.views where table_schema='public'` = 7 (6 + `miembros_alertas`)
- [ ] `select count(*) from pg_policies where schemaname='public'` coincide con producción
- [ ] `select relname from pg_class ... where relrowsecurity` coincide con producción
- [ ] `pg_cron` habilitado y el job `purge-deleted-torneos` programado
- [ ] Buckets `club-logos` y `player-photos` creados
- [ ] Existe la cuenta de administración de prueba y puede entrar
- [ ] No hay SMTP configurado
- [ ] No hay credenciales de pago configuradas
- [ ] El banner de staging se ve en todas las pantallas
- [ ] La URL de staging **no** aparece en ningún fichero commiteado
- [ ] El ejercicio de restauración quedó hecho (cierra el riesgo pendiente
      desde la Fase 0)

---

## Lo que sigue

Con staging en pie se desbloquea el resto de la Fase 1: roles reales (1.2),
endurecimiento de RLS (1.3), atribución de la auditoría (1.4) y Developer
Mode (1.5) — todo probado aquí antes de tocar producción.
