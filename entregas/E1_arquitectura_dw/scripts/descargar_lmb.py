"""
Descarga el calendario de los Diablos Rojos del Mexico (2022-2026) desde la
MLB Stats API y lo guarda como CSV para cargarlo a aymd_staging.stg_lmb_juegos.

Fuente:  https://statsapi.mlb.com/api/v1/schedule
         sportId=23 (Independent Leagues), Liga Mexicana = leagueId 125,
         Diablos Rojos del Mexico = teamId 532, Estadio Alfredo Harp Helu = venue 5340.
Uso:     python descargar_lmb.py            (solo biblioteca estandar de Python 3)
Salida:  datos_locales/lmb_juegos_2022_2026.csv

Es STAGING: se copian los campos tal como vienen (sin limpiar). Se conservan
juegos de visitante, pospuestos, dobles carteleras y filas repetidas de juegos
suspendidos/reanudados; la limpieza es trabajo de la fase de preparacion.

Terminos de uso de MLBAM: uso individual, no comercial y no masivo. Este script
hace 5 peticiones (una por temporada).
"""
import csv
import datetime as dt
import json
import os
import time
import urllib.request

TEMPORADAS = [2022, 2023, 2024, 2025, 2026]
URL = ("https://statsapi.mlb.com/api/v1/schedule?sportId=23&teamId=532"
       "&startDate={a}-03-01&endDate={a}-10-31&hydrate=gameInfo,weather")
SALIDA = os.path.join("datos_locales", "lmb_juegos_2022_2026.csv")

COLUMNAS = [
    "game_pk", "season", "official_date", "game_date_utc", "game_type",
    "series_description", "games_in_series", "series_game_number",
    "double_header", "game_number", "day_night", "status_detallado",
    "status_codigo", "status_razon", "home_team_id", "home_team_name",
    "away_team_id", "away_team_name", "home_score", "away_score",
    "home_is_winner", "home_wins", "home_losses", "home_pct",
    "away_wins", "away_losses", "away_pct", "venue_id", "venue_name",
    "attendance", "first_pitch_utc", "game_duration_minutes",
    "weather_condition", "weather_temp_f", "weather_wind", "descargado_en",
]


def g(d, *ruta):
    """Navega un dict anidado sin fallar si falta una llave."""
    for k in ruta:
        if not isinstance(d, dict):
            return None
        d = d.get(k)
    return d


def main():
    os.makedirs("datos_locales", exist_ok=True)
    ahora = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    filas = []
    for a in TEMPORADAS:
        url = URL.format(a=a)
        print("Descargando", url)
        req = urllib.request.Request(url, headers={"User-Agent": "UNAM-AyMD-E1 (proyecto academico)"})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.load(r)
        n = 0
        for fecha in data.get("dates", []):
            for j in fecha.get("games", []):
                home, away = g(j, "teams", "home"), g(j, "teams", "away")
                filas.append({
                    "game_pk": j.get("gamePk"),
                    "season": j.get("season"),
                    "official_date": j.get("officialDate"),
                    "game_date_utc": j.get("gameDate"),
                    "game_type": j.get("gameType"),
                    "series_description": j.get("seriesDescription"),
                    "games_in_series": j.get("gamesInSeries"),
                    "series_game_number": j.get("seriesGameNumber"),
                    "double_header": j.get("doubleHeader"),
                    "game_number": j.get("gameNumber"),
                    "day_night": j.get("dayNight"),
                    "status_detallado": g(j, "status", "detailedState"),
                    "status_codigo": g(j, "status", "codedGameState"),
                    "status_razon": g(j, "status", "reason"),
                    "home_team_id": g(home, "team", "id"),
                    "home_team_name": g(home, "team", "name"),
                    "away_team_id": g(away, "team", "id"),
                    "away_team_name": g(away, "team", "name"),
                    "home_score": g(home, "score"),
                    "away_score": g(away, "score"),
                    "home_is_winner": g(home, "isWinner"),
                    "home_wins": g(home, "leagueRecord", "wins"),
                    "home_losses": g(home, "leagueRecord", "losses"),
                    "home_pct": g(home, "leagueRecord", "pct"),
                    "away_wins": g(away, "leagueRecord", "wins"),
                    "away_losses": g(away, "leagueRecord", "losses"),
                    "away_pct": g(away, "leagueRecord", "pct"),
                    "venue_id": g(j, "venue", "id"),
                    "venue_name": g(j, "venue", "name"),
                    "attendance": g(j, "gameInfo", "attendance"),
                    "first_pitch_utc": g(j, "gameInfo", "firstPitch"),
                    "game_duration_minutes": g(j, "gameInfo", "gameDurationMinutes"),
                    "weather_condition": g(j, "weather", "condition"),
                    "weather_temp_f": g(j, "weather", "temp"),
                    "weather_wind": g(j, "weather", "wind"),
                    "descargado_en": ahora,
                })
                n += 1
        print(f"  temporada {a}: {n} filas")
        time.sleep(1)

    with open(SALIDA, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=COLUMNAS)
        w.writeheader()
        w.writerows(filas)
    locales = sum(1 for x in filas if str(x["venue_id"]) == "5340")
    print(f"\nListo: {SALIDA} · {len(filas)} filas ({locales} en el Estadio Alfredo Harp Helu)")


if __name__ == "__main__":
    main()
