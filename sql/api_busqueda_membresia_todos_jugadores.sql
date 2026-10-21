-- Renewal search: preserve the existing public ratings API, but make every official
-- Member ID searchable when linking a membership request to an existing player.
-- Exposes NO DOB, email, home address, telephone, payment data or guardian info.
CREATE OR REPLACE FUNCTION internal_security.safe_membership_directory()
RETURNS TABLE (
  member_id bigint,
  nombre text,
  apellido text,
  nombre_completo text,
  club text,
  rating numeric,
  membresia_activa boolean,
  membresia_vence date,
  nombre_busqueda text,
  member_id_text text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
  SELECT
    b."Member ID" AS member_id,
    btrim(b."First Name") AS nombre,
    btrim(b."Last Name") AS apellido,
    btrim(concat_ws(' ', btrim(b."First Name"), btrim(b."Last Name"))) AS nombre_completo,
    nullif(btrim(b."Club"), '') AS club,
    coalesce(b."New Rating", b."Rating"::numeric) AS rating,
    coalesce(public.fprtm_parse_fecha(b."Expiration Date") >= current_date, false) AS membresia_activa,
    public.fprtm_parse_fecha(b."Expiration Date") AS membresia_vence,
    translate(
      lower(regexp_replace(btrim(concat_ws(' ', b."First Name", b."Last Name")), '[[:space:]]+', ' ', 'g')),
      'áàäâãéèëêíìïîóòöôõúùüûñç',
      'aaaaaeeeeiiiiooooouuuunc'
    ) AS nombre_busqueda,
    b."Member ID"::text AS member_id_text
  FROM public."Base de Datos" b
  WHERE b."Member ID" IS NOT NULL
$function$;

-- Internal function is callable only through the narrowly scoped public view.
REVOKE ALL ON FUNCTION internal_security.safe_membership_directory() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION internal_security.safe_membership_directory() TO anon, authenticated;
CREATE OR REPLACE VIEW public.api_busqueda_membresia WITH (security_invoker=true) AS
  SELECT * FROM internal_security.safe_membership_directory();
REVOKE ALL ON public.api_busqueda_membresia FROM PUBLIC;
GRANT SELECT ON public.api_busqueda_membresia TO anon, authenticated, service_role;

-- The old composite primary key did not prevent reusing an existing Member ID
-- for a different person. The official Member IDs were checked for uniqueness.
CREATE UNIQUE INDEX IF NOT EXISTS base_member_id_unique_idx
  ON public."Base de Datos" ("Member ID");
