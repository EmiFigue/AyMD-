-- =====================================================================
-- E1 · Arquitectura del DW · Capa STAGING
-- Proyecto: Asistencia en el Estadio Alfredo Harp Helú (Diablos Rojos)
-- Ejecutar en la consola de BigQuery, dentro del proyecto del equipo.
--
-- Los TRES datasets se crean en la misma ubicación (US): la fuente pública
-- NOAA GSOD vive en la multirregión US y BigQuery no permite consultas
-- entre datasets de regiones distintas.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0) Crear los tres datasets (uno por capa) en la misma ubicación
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS aymd_staging
  OPTIONS (location = 'US',
           description = 'Capa staging (E1): datos crudos tal como vienen de cada fuente, sin limpiar ni transformar.');

CREATE SCHEMA IF NOT EXISTS aymd_dw
  OPTIONS (location = 'US',
           description = 'Capa DW (E1): esquema estrella (hechos_juego + 5 dimensiones).');

CREATE SCHEMA IF NOT EXISTS aymd_mart
  OPTIONS (location = 'US',
           description = 'Capa DataMart (E1): vistas que responden las preguntas de E0 con logica OLAP.');

-- ---------------------------------------------------------------------
-- 1) NOAA GSOD (dataset publico de BigQuery)
--    Paso 1a: localizar la estacion del Aeropuerto Internacional de la
--    Ciudad de Mexico (codigo OACI MMMX), a ~3 km del estadio.
-- ---------------------------------------------------------------------
SELECT usaf, wban, name, country, call, lat, lon, elev, `begin`, `end`
FROM `bigquery-public-data.noaa_gsod.stations`
WHERE call = 'MMMX';

-- Paso 1b: copiar a staging los registros diarios CRUDOS de esa estacion
-- (2022-2026). No se transforma nada: temperaturas siguen en grados F,
-- precipitacion en pulgadas y los faltantes con sus centinelas (9999.9 / 99.99).
-- Escanea ~2-3 GB de la tabla publica (cabe holgado en los creditos).
CREATE OR REPLACE TABLE aymd_staging.stg_noaa_gsod_mmmx
OPTIONS (description = 'Fuente: bigquery-public-data.noaa_gsod (NOAA GSOD), estacion MMMX. Copia cruda 2022-2026. Responde: P1, P2a, P3.')
AS
SELECT
  g.*,
  _TABLE_SUFFIX AS tabla_origen
FROM `bigquery-public-data.noaa_gsod.gsod*` AS g
WHERE _TABLE_SUFFIX BETWEEN '2022' AND '2026'
  AND g.stn IN (
    SELECT usaf
    FROM `bigquery-public-data.noaa_gsod.stations`
    WHERE call = 'MMMX'
  );

-- ---------------------------------------------------------------------
-- 2) Tablas cargadas desde archivo (consola: Crear tabla > Subir > CSV,
--    esquema con deteccion automatica). Nombres esperados:
--      aymd_staging.stg_lmb_juegos          <- lmb_juegos_2022_2026.csv
--      aymd_staging.stg_metro_afluencia     <- metro_afluencia_entorno_ahh.csv
--      aymd_staging.stg_fgj_carpetas        <- fgj_carpetas_entorno_ahh.csv
--    Despues de cargarlas, documentar fuente y fecha de carga:
-- ---------------------------------------------------------------------
ALTER TABLE aymd_staging.stg_lmb_juegos
  SET OPTIONS (description = 'Fuente: MLB Stats API (statsapi.mlb.com), Liga Mexicana (leagueId 125), equipo 532. Calendario + gameInfo + weather 2022-2026, crudo. Cargada: AAAA-MM-DD.');

ALTER TABLE aymd_staging.stg_metro_afluencia
  SET OPTIONS (description = 'Fuente: Afluencia diaria del Metro CDMX (desglosada), datos.cdmx.gob.mx. Muestra: estaciones Ciudad Deportiva, Velodromo y Puebla (L9), 2022-2026, crudo. Cargada: AAAA-MM-DD.');

ALTER TABLE aymd_staging.stg_fgj_carpetas
  SET OPTIONS (description = 'Fuente: Carpetas de investigacion FGJ CDMX, datos.cdmx.gob.mx. Muestra: hechos a <= 2 km del estadio, 2022-2026, crudo. Cargada: AAAA-MM-DD.');

-- ---------------------------------------------------------------------
-- 3) Verificacion rapida de cada tabla de staging (COUNT y rangos; no
--    usar SELECT * para no escanear de mas).
-- ---------------------------------------------------------------------
SELECT 'stg_lmb_juegos' AS tabla, COUNT(*) AS filas,
       MIN(CAST(official_date AS STRING)) AS desde,
       MAX(CAST(official_date AS STRING)) AS hasta
FROM aymd_staging.stg_lmb_juegos
UNION ALL
SELECT 'stg_noaa_gsod_mmmx', COUNT(*),
       MIN(CONCAT(year, '-', mo, '-', da)),
       MAX(CONCAT(year, '-', mo, '-', da))
FROM aymd_staging.stg_noaa_gsod_mmmx
UNION ALL
SELECT 'stg_metro_afluencia', COUNT(*),
       MIN(CAST(fecha AS STRING)), MAX(CAST(fecha AS STRING))
FROM aymd_staging.stg_metro_afluencia
UNION ALL
SELECT 'stg_fgj_carpetas', COUNT(*),
       MIN(CAST(fecha_hecho AS STRING)), MAX(CAST(fecha_hecho AS STRING))
FROM aymd_staging.stg_fgj_carpetas;
