# Night sky

A bar widget for the [Omarchy](https://omarchy.org) shell, made for planning night and twilight photography.

![The night panel](preview.png)

The pill shows the next sunrise or sunset, tonight's moon phase and how long the moon-free darkness lasts. A cloud glyph appears when the dark hours are mostly clouded over, and an aurora glyph when the Kp forecast reaches your threshold.

Click it for the night panel:

- **Sky chart** from evening golden hour to the end of morning golden hour, coloured by the sun's altitude: golden hour (+6° to −4°), blue hour (−4° to −6°), twilight, and night. Sun, moon and Milky Way core altitude are drawn over it; the core line is bold where it is at least 10° up in moon-free dark. A red line marks now.
- **Clouds** by the hour and **aurora** (planetary Kp in 3-hour bins) along the same time axis.
- **Evening and morning** times: golden hour, sunset, blue hour, astronomical dark, dawn, sunrise.
- **Where to point**: the core's best time, altitude and compass direction, and where the moon rises.

‹ › or the scroll wheel step to other nights. Right click refreshes.

## Install

```bash
omarchy plugin add https://github.com/buschbrian/omarchy-night-sky.git --enable
```

Plugins install disabled unless you pass `--enable`, so you can read the code first. The widget lands in the right section; move it with `omarchy bar move buschbrian.night-sky --section <left|center|right>`.

To open the panel from a key, bind `omarchy-shell buschbrian.night-sky toggle`.

## Settings

| Setting | Default | |
|---|---|---|
| Latitude / Longitude | empty | Decimal degrees. Empty uses the location set in Omarchy's weather panel. |
| Aurora Kp | 6 | Kp that flags an aurora chance. About 6 near 40–45° latitude; lower further poleward. |
| Clouds and Kp | on | Off keeps the widget fully offline. |
| Refresh (minutes) | 10 | |

Times are shown in the system time zone.

## Data

- **Astronomy** is computed locally with the Python standard library: the sun from Meeus ch. 25, the moon from Meeus ch. 47 with topocentric parallax. It is checked against golden vectors from [dark-sky-shot-planner](https://github.com/buschbrian/dark-sky-shot-planner), which were generated with astronomy-engine.
- **Clouds**: [Open-Meteo](https://open-meteo.com) hourly cloud cover. Your coordinates are sent with this request.
- **Kp**: [NOAA SWPC](https://www.swpc.noaa.gov) planetary K-index forecast. No location is sent.

Both are fetched at most once an hour and cached in `~/.cache/night-sky/`. Without a network, the panel leaves those lanes out.

Needs `python3`, which Omarchy ships, and a Nerd Font in the bar, which is Omarchy's default.

## Development

```bash
python3 -m unittest discover -s tests
python3 bin/night-sky --bar --lat 40.76 --lon -111.89 --date 2026-10-20 | python3 -m json.tool
omarchy plugin validate .
```

## License

MIT
