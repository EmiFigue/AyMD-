-- =====================================================================
-- E1 · Arquitectura del DW · Capa DW (esquema estrella)
-- Grano de hechos_juego: una fila por juego disputado por los Diablos
-- Rojos del Mexico como local en el Estadio Alfredo Harp Helu.
-- Las tablas se crean vacias: poblarlas corresponde a la fase de
-- preparacion de los datos (entrega posterior).
-- Ejecutar en este orden (primero dimensiones, luego hechos).
-- =====================================================================

-- ---------------------------------------------------------------------
-- dim_fecha · SCD tipo 0 (el calendario no cambia)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE aymd_dw.dim_fecha (
  fecha_key        INT64  NOT NULL,  -- llave sustituta inteligente AAAAMMDD
  fecha            DATE   NOT NULL,
  anio             INT64,
  mes              INT64,
  nombre_mes       STRING,
  dia              INT64,
  dia_semana_num   INT64,            -- 1 = lunes ... 7 = domingo (ISO)
  nombre_dia       STRING,
  semana_iso       INT64,
  es_fin_semana    BOOL,             -- viernes a domingo
  es_dia_valle     BOOL,             -- martes, miercoles o jueves (definicion de E0)
  es_quincena      BOOL,             -- dia de pago (15 o ultimo del mes) y 2 dias siguientes
  es_festivo       BOOL,             -- descanso obligatorio LFT art. 74 o asueto de Semana Santa
  nombre_festivo   STRING,
  temporada_lmb    INT64,
  PRIMARY KEY (fecha_key) NOT ENFORCED
)
OPTIONS (description = 'Dimension de tiempo, grano dia. SCD tipo 0. Responde: P1, P2a, P3.');

-- ---------------------------------------------------------------------
-- dim_rival · SCD tipo 2 (los equipos de la LMB se mudan, cambian de
-- nombre o de zona; se conserva la version vigente en cada juego)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE aymd_dw.dim_rival (
  rival_key            INT64  NOT NULL,  -- llave sustituta secuencial
  team_id_api          INT64  NOT NULL,  -- llave natural (MLB Stats API)
  nombre_equipo        STRING,
  nombre_corto         STRING,
  abreviatura          STRING,
  ciudad               STRING,
  zona                 STRING,           -- Norte / Sur
  estadio_local        STRING,
  es_rival_misma_zona  BOOL,             -- TRUE si juega en la Zona Sur, como los Diablos
  valido_desde         DATE   NOT NULL,
  valido_hasta         DATE,             -- NULL = version vigente
  es_version_actual    BOOL   NOT NULL,
  PRIMARY KEY (rival_key) NOT ENFORCED
)
OPTIONS (description = 'Equipo visitante. SCD tipo 2. Responde: P1, P2a, P3.');

-- ---------------------------------------------------------------------
-- dim_horario · SCD tipo 0 (catalogo fijo de horas de inicio)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE aymd_dw.dim_horario (
  horario_key        INT64  NOT NULL,  -- llave sustituta
  hora_inicio_local  INT64,            -- 0-23, hora de Ciudad de Mexico
  franja             STRING,           -- 'Mediodia (<16 h)', 'Tarde (16-18 h)', 'Noche (>=19 h)'
  dia_noche_api      STRING,           -- 'day' / 'night' tal como lo reporta la API
  PRIMARY KEY (horario_key) NOT ENFORCED
)
OPTIONS (description = 'Hora de inicio del juego. SCD tipo 0. Responde: P1, P2a, P3.');

-- ---------------------------------------------------------------------
-- dim_clima · SCD tipo 0 (catalogo de bandas; un juego se asocia a la
-- banda observada ese dia, no se actualiza)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE aymd_dw.dim_clima (
  clima_key           INT64  NOT NULL,  -- llave sustituta
  condicion_api       STRING,           -- 'Cloudy', 'Partly Cloudy', 'Rain'... (MLB Stats API)
  condicion_es        STRING,           -- traduccion al espanol
  categoria_lluvia    STRING,           -- 'Sin lluvia', 'Ligera (<5 mm)', 'Moderada (5-20 mm)', 'Fuerte (>20 mm)' (NOAA GSOD)
  rango_temperatura   STRING,           -- 'Fresco (<18 C)', 'Templado (18-24 C)', 'Calido (>24 C)' (NOAA GSOD, maxima)
  PRIMARY KEY (clima_key) NOT ENFORCED
)
OPTIONS (description = 'Condicion meteorologica del dia del juego en bandas. SCD tipo 0. Responde: P1, P2a, P3.');

-- ---------------------------------------------------------------------
-- dim_tipo_juego · SCD tipo 0 (catalogo de fases y formato del juego)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE aymd_dw.dim_tipo_juego (
  tipo_juego_key         INT64  NOT NULL,  -- llave sustituta
  game_type_api          STRING,           -- R, F, D, L, W (MLB Stats API)
  fase                   STRING,           -- 'Temporada regular' / 'Postemporada'
  ronda                  STRING,           -- seriesDescription: 'Primera Ronda de Playoffs', 'Serie del Rey'...
  es_doble_cartelera     BOOL,
  numero_juego_en_serie  INT64,
  juegos_en_serie        INT64,
  PRIMARY KEY (tipo_juego_key) NOT ENFORCED
)
OPTIONS (description = 'Fase y formato del juego. SCD tipo 0. Responde: P1, P2a, P3.');

-- ---------------------------------------------------------------------
-- hechos_juego · grano: un juego local en el Estadio Alfredo Harp Helu
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE aymd_dw.hechos_juego (
  juego_id                 INT64  NOT NULL,  -- gamePk de la API (dimension degenerada)
  fecha_key                INT64  NOT NULL,
  rival_key                INT64  NOT NULL,
  horario_key              INT64  NOT NULL,
  clima_key                INT64  NOT NULL,
  tipo_juego_key           INT64  NOT NULL,
  asistencia               INT64,    -- aditiva
  pct_ocupacion            FLOAT64,  -- no aditiva: asistencia / 20062 (aforo)
  carreras_diablos         INT64,    -- aditiva
  carreras_rival           INT64,    -- aditiva
  gano_diablos             INT64,    -- aditiva (0/1; su suma = victorias)
  pct_victorias_previo     FLOAT64,  -- no aditiva: % de victorias antes del juego
  duracion_min             INT64,    -- no aditiva
  temp_juego_c             FLOAT64,  -- no aditiva: temperatura al inicio (API, convertida de F)
  temp_max_dia_c           FLOAT64,  -- no aditiva: maxima del dia (NOAA GSOD)
  precipitacion_dia_mm     FLOAT64,  -- semiaditiva: suma en el tiempo, no entre juegos del mismo dia
  afluencia_metro_entorno  INT64,    -- semiaditiva: entradas del dia en Cd. Deportiva + Velodromo + Puebla
  delitos_entorno_dia      INT64,    -- semiaditiva: carpetas FGJ a <= 2 km del estadio ese dia
  PRIMARY KEY (juego_id) NOT ENFORCED,
  FOREIGN KEY (fecha_key)      REFERENCES aymd_dw.dim_fecha (fecha_key)           NOT ENFORCED,
  FOREIGN KEY (rival_key)      REFERENCES aymd_dw.dim_rival (rival_key)           NOT ENFORCED,
  FOREIGN KEY (horario_key)    REFERENCES aymd_dw.dim_horario (horario_key)       NOT ENFORCED,
  FOREIGN KEY (clima_key)      REFERENCES aymd_dw.dim_clima (clima_key)           NOT ENFORCED,
  FOREIGN KEY (tipo_juego_key) REFERENCES aymd_dw.dim_tipo_juego (tipo_juego_key) NOT ENFORCED
)
OPTIONS (description = 'Grano: una fila por juego disputado por los Diablos Rojos como local en el Estadio Alfredo Harp Helu (2022-2026). Responde: P1, P2a, P3.');
