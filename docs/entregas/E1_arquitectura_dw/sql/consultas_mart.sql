-- =====================================================================
-- E1 · Arquitectura del DW · Capa DataMart
-- Una vista por pregunta de E0 (P4 no se puede responder con el diseno;
-- ver la justificacion al final). Logica OLAP usada:
--   ROLLUP (P1a, P1b) · CUBE (P3b) · funciones de ventana (P2a, P3a)
-- Las tablas del DW estan vacias en E1: las vistas deben ser validas
-- (sintaxis y referencias), no es necesario que devuelvan filas.
-- =====================================================================

-- ---------------------------------------------------------------------
-- P1 · ¿Que variables predicen mejor la asistencia con >= 48 h de
-- anticipacion?  (Regresion)
-- P1a: asistencia promedio por dia de la semana, franja horaria y zona
-- del rival, con subtotales jerarquicos (ROLLUP).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW aymd_mart.vw_p1a_asistencia_contexto
OPTIONS (description = 'Responde P1: asistencia promedio por dia, franja y zona del rival con subtotales ROLLUP.')
AS
SELECT
  f.nombre_dia,
  h.franja,
  r.zona                          AS zona_rival,
  COUNT(*)                        AS juegos,
  ROUND(AVG(j.asistencia), 0)     AS asistencia_promedio,
  ROUND(AVG(j.pct_ocupacion), 3)  AS ocupacion_promedio,
  GROUPING(f.nombre_dia)          AS es_subtotal_dia,
  GROUPING(h.franja)              AS es_subtotal_franja,
  GROUPING(r.zona)                AS es_subtotal_zona
FROM aymd_dw.hechos_juego        AS j
JOIN aymd_dw.dim_fecha           AS f ON j.fecha_key      = f.fecha_key
JOIN aymd_dw.dim_horario         AS h ON j.horario_key    = h.horario_key
JOIN aymd_dw.dim_rival           AS r ON j.rival_key      = r.rival_key
JOIN aymd_dw.dim_tipo_juego      AS t ON j.tipo_juego_key = t.tipo_juego_key
WHERE t.fase = 'Temporada regular'
GROUP BY ROLLUP (f.nombre_dia, h.franja, r.zona);

-- ---------------------------------------------------------------------
-- P1b: correlacion de la asistencia con las variables numericas
-- candidatas, por temporada y total (ROLLUP).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW aymd_mart.vw_p1b_correlaciones
OPTIONS (description = 'Responde P1: correlacion de Pearson entre asistencia y clima, rendimiento y delitos del entorno, por temporada y total.')
AS
SELECT
  f.temporada_lmb,
  COUNT(*)                                             AS juegos,
  ROUND(CORR(j.asistencia, j.temp_max_dia_c), 3)       AS corr_temp_max,
  ROUND(CORR(j.asistencia, j.precipitacion_dia_mm), 3) AS corr_lluvia,
  ROUND(CORR(j.asistencia, j.pct_victorias_previo), 3) AS corr_rendimiento_previo,
  ROUND(CORR(j.asistencia, j.delitos_entorno_dia), 3)  AS corr_delitos_entorno,
  GROUPING(f.temporada_lmb)                            AS es_total
FROM aymd_dw.hechos_juego   AS j
JOIN aymd_dw.dim_fecha      AS f ON j.fecha_key      = f.fecha_key
JOIN aymd_dw.dim_tipo_juego AS t ON j.tipo_juego_key = t.tipo_juego_key
WHERE t.fase = 'Temporada regular'
GROUP BY ROLLUP (f.temporada_lmb);

-- ---------------------------------------------------------------------
-- P2a (ajustada, ver pivote.qmd) · ¿Que perfiles de juego existen segun
-- su asistencia, contexto y movilidad de llegada?  (Clustering)
-- Vector de caracteristicas por juego, estandarizado dentro de cada
-- temporada con funciones de ventana (insumo directo para k-means).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW aymd_mart.vw_p2a_perfil_juegos
OPTIONS (description = 'Responde P2a: caracteristicas estandarizadas por juego para segmentar perfiles de jornada.')
AS
SELECT
  j.juego_id,
  f.fecha,
  f.temporada_lmb,
  f.nombre_dia,
  f.es_dia_valle,
  h.franja,
  r.nombre_corto                                              AS rival,
  t.fase,
  c.categoria_lluvia,
  j.asistencia,
  j.pct_ocupacion,
  j.afluencia_metro_entorno,
  SAFE_DIVIDE(j.afluencia_metro_entorno, j.asistencia)        AS razon_metro_asistencia,
  h.hora_inicio_local + j.duracion_min / 60                   AS hora_salida_estimada,
  SAFE_DIVIDE(j.asistencia - AVG(j.asistencia) OVER w_temporada,
              STDDEV_SAMP(j.asistencia) OVER w_temporada)     AS z_asistencia,
  SAFE_DIVIDE(j.afluencia_metro_entorno - AVG(j.afluencia_metro_entorno) OVER w_temporada,
              STDDEV_SAMP(j.afluencia_metro_entorno) OVER w_temporada) AS z_metro,
  PERCENT_RANK() OVER (PARTITION BY f.temporada_lmb ORDER BY j.asistencia) AS percentil_asistencia
FROM aymd_dw.hechos_juego   AS j
JOIN aymd_dw.dim_fecha      AS f ON j.fecha_key      = f.fecha_key
JOIN aymd_dw.dim_horario    AS h ON j.horario_key    = h.horario_key
JOIN aymd_dw.dim_rival      AS r ON j.rival_key      = r.rival_key
JOIN aymd_dw.dim_tipo_juego AS t ON j.tipo_juego_key = t.tipo_juego_key
JOIN aymd_dw.dim_clima      AS c ON j.clima_key      = c.clima_key
WINDOW w_temporada AS (PARTITION BY f.temporada_lmb);

-- ---------------------------------------------------------------------
-- P3 · ¿Que juegos entre semana tienen mayor riesgo de no alcanzar la
-- meta de 9,500 asistentes?  (Clasificacion)
-- P3a: conjunto de entrenamiento. Etiqueta en_riesgo y variables que se
-- conocen con >= 48 h de anticipacion (ventanas que terminan 2 dias antes).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW aymd_mart.vw_p3a_dataset_riesgo_valle
OPTIONS (description = 'Responde P3: juegos de dia valle con etiqueta en_riesgo (< 9,500) y variables disponibles 48 h antes.')
AS
WITH base AS (
  SELECT
    j.juego_id,
    f.fecha,
    f.temporada_lmb,
    f.nombre_dia,
    f.es_dia_valle,
    f.es_quincena,
    f.es_festivo,
    r.team_id_api                  AS rival_id,
    r.nombre_corto                 AS rival,
    r.es_rival_misma_zona,
    h.franja,
    c.categoria_lluvia,
    c.rango_temperatura,
    j.pct_victorias_previo,
    j.delitos_entorno_dia,
    j.asistencia
  FROM aymd_dw.hechos_juego   AS j
  JOIN aymd_dw.dim_fecha      AS f ON j.fecha_key      = f.fecha_key
  JOIN aymd_dw.dim_rival      AS r ON j.rival_key      = r.rival_key
  JOIN aymd_dw.dim_horario    AS h ON j.horario_key    = h.horario_key
  JOIN aymd_dw.dim_clima      AS c ON j.clima_key      = c.clima_key
  JOIN aymd_dw.dim_tipo_juego AS t ON j.tipo_juego_key = t.tipo_juego_key
  WHERE t.fase = 'Temporada regular'
),
con_historia AS (
  SELECT
    b.*,
    -- asistencia promedio de los juegos locales de los 30 dias previos,
    -- excluyendo las ultimas 48 h (dato disponible al decidir)
    AVG(b.asistencia) OVER (
      PARTITION BY b.temporada_lmb
      ORDER BY UNIX_DATE(b.fecha)
      RANGE BETWEEN 30 PRECEDING AND 2 PRECEDING
    ) AS asistencia_prom_30d_previos,
    -- asistencia promedio contra el mismo rival en visitas anteriores
    -- (hasta ~13 meses atras, sin contar la serie en curso)
    AVG(b.asistencia) OVER (
      PARTITION BY b.rival_id
      ORDER BY UNIX_DATE(b.fecha)
      RANGE BETWEEN 400 PRECEDING AND 3 PRECEDING
    ) AS asistencia_prom_rival_previa
  FROM base AS b
)
SELECT
  juego_id,
  fecha,
  temporada_lmb,
  nombre_dia,
  es_quincena,
  es_festivo,
  rival,
  es_rival_misma_zona,
  franja,
  categoria_lluvia,
  rango_temperatura,
  pct_victorias_previo,
  delitos_entorno_dia,
  asistencia_prom_30d_previos,
  asistencia_prom_rival_previa,
  asistencia,
  IF(asistencia < 9500, 1, 0) AS en_riesgo
FROM con_historia
WHERE es_dia_valle;

-- ---------------------------------------------------------------------
-- P3b: tasa de juegos en riesgo en dia valle por temporada, franja y
-- zona del rival, en todas sus combinaciones (CUBE).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW aymd_mart.vw_p3b_tasa_riesgo_cubo
OPTIONS (description = 'Responde P3: tasa de juegos en riesgo (< 9,500) en dia valle con CUBE sobre temporada, franja y zona del rival.')
AS
SELECT
  f.temporada_lmb,
  h.franja,
  r.zona                                                      AS zona_rival,
  COUNT(*)                                                    AS juegos_valle,
  COUNTIF(j.asistencia < 9500)                                AS juegos_en_riesgo,
  ROUND(SAFE_DIVIDE(COUNTIF(j.asistencia < 9500), COUNT(*)), 3) AS tasa_riesgo,
  GROUPING(f.temporada_lmb)                                   AS g_temporada,
  GROUPING(h.franja)                                          AS g_franja,
  GROUPING(r.zona)                                            AS g_zona
FROM aymd_dw.hechos_juego   AS j
JOIN aymd_dw.dim_fecha      AS f ON j.fecha_key      = f.fecha_key
JOIN aymd_dw.dim_horario    AS h ON j.horario_key    = h.horario_key
JOIN aymd_dw.dim_rival      AS r ON j.rival_key      = r.rival_key
JOIN aymd_dw.dim_tipo_juego AS t ON j.tipo_juego_key = t.tipo_juego_key
WHERE f.es_dia_valle
  AND t.fase = 'Temporada regular'
GROUP BY CUBE (f.temporada_lmb, h.franja, r.zona);

-- ---------------------------------------------------------------------
-- P4 · ¿Que factores se relacionan con un mayor gasto por persona en
-- comida, bebida y mercancia?  (Regresion / correlacion)
-- NO SE PUEDE RESPONDER CON ESTE DISENO: ninguna fuente publica registra
-- ventas dentro del estadio (punto de venta) ni boletaje por aficionado
-- (Ticketmaster / Pase Diablo son datos privados del club). Ver
-- trazabilidad.qmd y pivote.qmd. El esquema queda preparado para
-- agregar una segunda tabla de hechos (hechos_venta, grano: una linea de
-- ticket de venta) que comparta dim_fecha y juego_id cuando el club
-- comparta esos datos.
-- ---------------------------------------------------------------------
