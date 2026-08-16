-- ============================================================
--  FPTM — Pagos parciales en inscripciones
--  Ejecutar en: Supabase → SQL Editor
-- ============================================================

-- Monto realmente recibido. El booleano `pagado` se mantiene como
-- "pagado por completo" para no romper reportes existentes.
ALTER TABLE public.insc_registro
  ADD COLUMN IF NOT EXISTS monto_pagado NUMERIC DEFAULT 0;

-- Las inscripciones ya marcadas como pagadas quedan con su total cubierto
UPDATE public.insc_registro
SET monto_pagado = COALESCE(total, 0)
WHERE pagado = true AND COALESCE(monto_pagado, 0) = 0;

-- Verificar
SELECT nombre, total, monto_pagado, pagado,
       GREATEST(COALESCE(total,0) - COALESCE(monto_pagado,0), 0) AS balance
FROM public.insc_registro
ORDER BY balance DESC
LIMIT 20;
