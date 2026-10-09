# Night sky

A bar widget for the [Omarchy](https://omarchy.org) shell, made for planning night and twilight photography.

![The night panel](preview.png)

The pill shows the next sunrise or sunset, tonight's moon phase and how long the moon-free darkness lasts. A cloud glyph appears when the dark hours are mostly clouded over, and an aurora glyph when the Kp forecast reaches your threshold. The pill is highlighted on a night rated "go".

Click it for the night panel. **Tonight** has:

- **A shoot verdict**: go, marginal or no-go, plus the factor that decides it ("No-go · clouds 95%"). It uses a worst-factor rule over the moon-free dark window. The factors that can block a night are moon-free time, mean and worst-hour cloud, haze (aerosol optical depth) and wind gusts. Dew, core altitude and the jet stream are shown as advice. A factor with no data, or a forecast older than six hours, keeps the night at "marginal" at best. Aurora never lowers the verdict; it only adds a flag.
- **A sky chart** from evening golden hour to the end of morning golden hour, coloured by the sun's altitude: golden hour (+6° to −4°), blue hour (−4° to −6°), twilight, and night. Sun, moon and Milky Way core altitude are drawn over it. The core line is bold where it is at least 10° up in moon-free dark, and a red line marks now.
- **Lanes** along the same time axis:
  - cloud by layer (high, mid, low)
  - a seeing proxy from the 250 hPa jet-stream wind
  - planetary Kp in 3-hour bins
- **Every factor** behind the verdict, coloured by its rating.
- **Evening and morning times**: golden hour, sunset, blue hour, astronomical dark, dawn and sunrise.
- **Where to point**:
  - the core's best time, altitude and direction
  - its rise, highest point and set
  - where the moon rises
  - optionally, the longest exposure before stars trail, by the NPF and 500 rules, for your lens

**Week & events** has:

- **The next seven nights**: verdict colour, moon phase, moon-free hours and mean cloud. Click a night to open it.
- **The next 30 days**:
  - moon phases, equinoxes and solstices
  - meteor showers, judged where you are: does the radiant clear 10° in darkness, how long is it up with the moon down, and is a nearby night better?
  - curated festivals

‹ › or the scroll wheel step to other nights. Right click the pill refreshes.

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
| Clouds and Kp | on | Off keeps the widget fully offline (astronomy only). |
| Lens focal length, aperture, pixel pitch, crop factor | off | For the exposure helper. Focal length alone gives the 500 rule; add aperture and pixel pitch for the NPF rule at the core's declination. |
| Refresh (minutes) | 10 | |

Times are shown in the system time zone.

## Data

- **Astronomy** is computed locally with the Python standard library: the sun from Meeus ch. 25, the moon from Meeus ch. 47 with topocentric parallax, and shower radiants precessed from J2000 (Meeus 21.2). It is checked against golden vectors from [dark-sky-shot-planner](https://github.com/buschbrian/dark-sky-shot-planner), which were generated with astronomy-engine, and against published equinox and moon-phase times.
- **Verdict thresholds** (`data/conditions-thresholds.json`) and **curated showers and festivals** (`data/sky-events.json`) come from dark-sky-shot-planner (MIT). The events list is refreshed daily from that repo; the bundled copy is the fallback.
- **Weather**: [Open-Meteo](https://open-meteo.com) hourly forecast (cloud layers, gusts, temperature, dew point, 250 hPa wind) and air quality (aerosol optical depth, about five days ahead). Your coordinates are sent with these requests. Open-Meteo's free API is for non-commercial use.
- **Kp**: [NOAA SWPC](https://www.swpc.noaa.gov) planetary K-index observations and forecast. No location is sent.

Network data is fetched at most once an hour (the events list once a day) and cached in `~/.cache/night-sky/`. Without a network, the panel leaves those parts out and the verdict says the data is incomplete.

Needs `python3`, which Omarchy ships, and a Nerd Font in the bar, which is Omarchy's default.

## Development

```bash
python3 -m unittest discover -s tests
python3 bin/night-sky --bar --lat 40.76 --lon -111.89 --date 2026-10-20 | python3 -m json.tool
omarchy plugin validate .
```

## License

MIT
