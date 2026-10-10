"""
Recorta los CSV completos descargados de datos.cdmx.gob.mx a una MUESTRA del
entorno del Estadio Alfredo Harp Helu (2022-2026).

No transforma valores: solo selecciona filas y conserva todas las columnas
tal como vienen.

Si el script no encuentra una columna, imprime los encabezados reales del
archivo: ajusten los nombres en COLUMNAS_* y vuelvan a correrlo.
"""
import csv
import math
import os
import re
import sys
import unicodedata

ESTADIO_LAT, ESTADIO_LON = 19.404, -99.0855   # Estadio Alfredo Harp Helu (Wikipedia)
RADIO_KM = 2.0
ANIOS = {"2022", "2023", "2024", "2025", "2026"}
ESTACIONES_METRO = {"ciudad deportiva", "velodromo", "puebla"}

COLUMNAS_METRO = {"fecha": ["fecha"], "estacion": ["estacion", "estación"]}
COLUMNAS_FGJ = {"fecha": ["fecha_hecho"], "lat": ["latitud", "lat"], "lon": ["longitud", "lon"]}

csv.field_size_limit(10_000_000)


def norm(s):
    s = unicodedata.normalize("NFKD", (s or "").strip().lower())
    return "".join(c for c in s if not unicodedata.combining(c))


def abrir(ruta):
    for enc in ("utf-8-sig", "latin-1"):
        f = open(ruta, newline="", encoding=enc)
        try:
            f.read(5_000_000)  # detectar la codificacion con los primeros ~5 MB
            f.seek(0)
            return f, enc
        except UnicodeDecodeError:
            f.close()
    raise SystemExit(f"No se pudo leer {ruta} como UTF-8 ni Latin-1")


def buscar(encabezados, candidatos, nombre):
    mapa = {norm(h): h for h in encabezados}
    for c in candidatos:
        if norm(c) in mapa:
            return mapa[norm(c)]
    raise SystemExit(f"No encontre la columna '{nombre}'. Encabezados reales: {encabezados}")


def haversine_km(lat1, lon1, lat2, lon2):
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def filtrar(modo, entradas):
    os.makedirs("datos_locales", exist_ok=True)
    salida = os.path.join("datos_locales",
                          "metro_afluencia_entorno_ahh.csv" if modo == "metro"
                          else "fgj_carpetas_entorno_ahh.csv")
    columnas_salida = None
    leidas = escritas = sin_coord = 0
    with open(salida, "w", newline="", encoding="utf-8") as fo:
        w = None
        for entrada in entradas:
            f, enc = abrir(entrada)
            lector = csv.DictReader(f)
            enc_cols = lector.fieldnames
            print(f"{entrada}: codificacion {enc}, {len(enc_cols)} columnas")
            if columnas_salida is None:
                columnas_salida = enc_cols
                w = csv.DictWriter(fo, fieldnames=columnas_salida, extrasaction="ignore")
                w.writeheader()
            elif enc_cols != columnas_salida:
                print("  AVISO: este archivo tiene columnas distintas al primero; "
                      "las que no existan en el primero se omiten (documentarlo).")
            if modo == "metro":
                c_fecha = buscar(enc_cols, COLUMNAS_METRO["fecha"], "fecha")
                c_est = buscar(enc_cols, COLUMNAS_METRO["estacion"], "estacion")
            else:
                c_fecha = buscar(enc_cols, COLUMNAS_FGJ["fecha"], "fecha_hecho")
                c_lat = buscar(enc_cols, COLUMNAS_FGJ["lat"], "latitud")
                c_lon = buscar(enc_cols, COLUMNAS_FGJ["lon"], "longitud")
            for fila in lector:
                leidas += 1
                m = re.search(r"(20\d{2})", fila.get(c_fecha) or "")
                if not m or m.group(1) not in ANIOS:
                    continue
                if modo == "metro":
                    if norm(fila.get(c_est)) not in ESTACIONES_METRO:
                        continue
                else:
                    try:
                        lat, lon = float(fila[c_lat]), float(fila[c_lon])
                    except (TypeError, ValueError):
                        sin_coord += 1
                        continue
                    if haversine_km(ESTADIO_LAT, ESTADIO_LON, lat, lon) > RADIO_KM:
                        continue
                w.writerow(fila)
                escritas += 1
            f.close()
    print(f"Filas leidas: {leidas:,} · escritas: {escritas:,} -> {salida}")
    if modo == "fgj":
        print(f"Filas 2022-2026 descartadas por no tener coordenadas: {sin_coord:,} (documentarlo en fuentes.qmd)")
    mb = os.path.getsize(salida) / 1_048_576
    print(f"Tamano de la muestra: {mb:.1f} MB (limite de la consola ~100 MB)")


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("metro", "fgj"):
        raise SystemExit(__doc__)
    filtrar(sys.argv[1], sys.argv[2:])
