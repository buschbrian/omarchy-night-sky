"""Offline checks for night-sky. tests/golden/night-report.json comes from
github.com/buschbrian/dark-sky-shot-planner (shared/golden, MIT), generated with astronomy-engine."""
from datetime import date, datetime, timedelta
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'bin/night-sky'
loader = importlib.machinery.SourceFileLoader('night_sky', str(path))
sky = importlib.util.module_from_spec(importlib.util.spec_from_loader('night_sky', loader))
loader.exec_module(sky)

GOLDEN = json.loads((Path(__file__).parent / 'golden/night-report.json').read_text())


def utc(text):
    return datetime.fromisoformat(text.replace('Z', '+00:00')) if text else None


class GoldenVectors(unittest.TestCase):
    def test_cases(self):
        tol = GOLDEN['tolerance']
        for case in GOLDEN['cases']:
            with self.subTest(case['id']):
                lat, lon = case['latitude'], case['longitude']
                plan = sky.plan_night(lat, lon, utc(case['evening_utc']) - timedelta(hours=12))
                self.check_night(plan, case['expected'], tol, lat, lon)

    def check_time(self, got, want, tol):
        if want is None:
            self.assertIsNone(got)
        else:
            self.assertIsNotNone(got, f'missing {want}')
            self.assertLessEqual(abs((got - utc(want)).total_seconds()), tol['time_s'], f'{got} vs {want}')

    def check_night(self, plan, exp, tol, lat, lon):
        dark = plan['darkness']
        if exp['no_astronomical_darkness']:
            self.assertIsNone(dark)
            return
        self.check_time(dark[0], exp['darkness']['start'], tol)
        self.check_time(dark[1], exp['darkness']['end'], tol)
        inside = lambda ts: next((t for t in ts if dark[0] <= t <= dark[1]), None)
        self.check_time(inside(plan['moonsets']), exp['moonset'], tol)
        self.check_time(inside(plan['moonrises']), exp['moonrise'], tol)
        illum = sky.phase_info(plan['phase_at'])['fraction']
        self.assertAlmostEqual(illum, exp['moon_illum_fraction'], delta=tol['illum_fraction'])
        self.assertEqual(len(plan['moon_free']), len(exp['moon_free_windows']))
        for got, want in zip(plan['moon_free'], exp['moon_free_windows']):
            self.check_time(got[0], want['start'], tol)
            self.check_time(got[1], want['end'], tol)
            self.assertAlmostEqual(sky.minutes(got), want['minutes'], delta=tol['minutes'])
        best = None
        for a, b in plan['moon_free']:
            t = a
            while t <= b:
                best = max(best or (-90, t), (sky.core_altitude(t, lat, lon), t))
                t += timedelta(minutes=1)
        want = exp['gc']['max_altitude_deg']
        if want is None:
            self.assertIsNone(best)
        else:
            self.assertAlmostEqual(best[0], want, delta=tol['altitude_deg'])


class Reports(unittest.TestCase):
    def test_full_moon_skips_core(self):
        report = sky.tonight(40.76, -111.89, date(2026, 12, 21))
        self.assertEqual(report['verdict_class'], 'skip')
        self.assertIn('skip core shots', report['verdict'])

    def test_summer_core_is_a_go(self):
        report = sky.tonight(38.374031, -109.965416, date(2026, 6, 15))
        self.assertEqual(report['verdict_class'], 'go')
        self.assertTrue(report['verdict'].startswith('Go: '))

    def test_no_darkness_at_high_latitude(self):
        report = sky.tonight(48.99, -114.0, date(2026, 6, 20))
        self.assertEqual(report['verdict_class'], 'none')
        self.assertEqual(sky.bar_output(report)['class'], 'none')

    def test_bar_shape(self):
        out = sky.bar_output(sky.tonight(40.6869, -111.838, date(2026, 10, 8)))
        self.assertEqual(sorted(out), ['class', 'text', 'tooltip'])

    def test_bar_merges_sun_and_panel_timeline(self):
        lat, lon = 40.6869, -111.838
        noon = datetime(2026, 10, 20, 12, tzinfo=sky.ZoneInfo('America/Denver'))
        sun = sky.sun_report(lat, lon, noon, 'America/Denver')
        out = sky.bar_output(sky.tonight(lat, lon, date(2026, 10, 20), 'America/Denver'), sun, lat, lon)
        self.assertTrue(out['text'].startswith(sun['text']))
        self.assertNotIn('dark', out['text'])
        line = out['panel']['timeline']
        bands = line['sky']
        self.assertEqual([b['kind'] for b in bands],
                         ['golden', 'blue', 'twilight', 'dark', 'twilight', 'blue', 'golden'])
        self.assertEqual((bands[0]['a'], bands[-1]['b']), (0.0, 1.0))
        for prev, nxt in zip(bands, bands[1:]):
            self.assertEqual(prev['b'], nxt['a'])
        evening, morning = line['events']['evening'], line['events']['morning']
        self.assertLess(evening['golden'], evening['sunset'])
        self.assertLess(evening['sunset'], evening['blue'])
        self.assertLess(evening['blue'], evening['blue_end'])
        self.assertLess(morning['blue'], morning['golden'])
        self.assertLess(morning['sunrise'], morning['golden_end'])
        self.assertEqual(len(line['curves']['sun']), len(line['curves']['core']))
        self.assertTrue(out['panel']['moon']['waxing'])
        self.assertEqual(len(line['moon']), 1)  # waxing gibbous, up at dusk, sets after midnight
        self.assertTrue(all(0 <= s['a'] <= s['b'] <= 1 for s in line['moon'] + line['core']))
        self.assertIsNone(line['clouds'])
        self.assertIsNone(line['kp'])

    def test_clouds_and_aurora_flag_the_pill(self):
        lat, lon = 40.6869, -111.838
        evening = datetime(2026, 10, 9, 18, tzinfo=sky.timezone.utc)
        clouds = [{'time': (evening + timedelta(hours=h)).strftime('%Y-%m-%dT%H:%M'),
                   'total': 90, 'low': 10, 'mid': 90, 'high': 0} for h in range(24)]
        kp = [{'time': (evening + timedelta(hours=h)).strftime('%Y-%m-%dT%H:%M:%S'), 'kp': 6.33,
               'observed': 'predicted', 'scale': 'G2'} for h in range(0, 24, 3)]
        out = sky.bar_output(sky.tonight(lat, lon, date(2026, 10, 9), 'America/Denver'), None, lat, lon, clouds, kp)
        line = out['panel']['timeline']
        self.assertEqual(line['cloud_pct'], 90)
        self.assertGreater(line['kp_max'], 6)
        self.assertTrue(out['text'].endswith(sky.CLOUD_GLYPH + ' ' + sky.AURORA_GLYPH))
        self.assertEqual(len(out['panel']['notes']), 2)
        best = line['core_best']
        self.assertEqual(best['dir'], sky.compass(best['az']))
        self.assertTrue(150 < best['az'] < 240)  # the core sits south of Utah

    def test_current_night_runs_until_sunrise(self):
        tz = sky.ZoneInfo('America/Denver')
        lat, lon = 40.6869, -111.838
        before_dawn = sky.current_night(lat, lon, datetime(2026, 10, 9, 3, tzinfo=tz), 'America/Denver')
        morning = sky.current_night(lat, lon, datetime(2026, 10, 9, 9, tzinfo=tz), 'America/Denver')
        self.assertEqual(before_dawn['date'], '2026-10-08')
        self.assertEqual(morning['date'], '2026-10-09')


class Sun(unittest.TestCase):
    SLC = (40.7608, -111.8910)

    def at(self, day, hhmm):
        from zoneinfo import ZoneInfo
        h, m = map(int, hhmm.split(':'))
        return datetime(*map(int, day.split('-')), h, m, tzinfo=ZoneInfo('America/Denver'))

    def close(self, got, want, tol=3):
        g, w = (int(x[:2]) * 60 + int(x[3:]) for x in (got, want))
        self.assertLessEqual(abs(g - w), tol, f'{got} vs {want}')

    def test_solstices_match_published_times(self):
        # NOAA solar calculator, Salt Lake City
        summer = sky.sun_report(*self.SLC, self.at('2026-06-21', '12:00'))
        self.close(summer['sunrise'], '05:57')
        self.close(summer['sunset'], '21:03')
        winter = sky.sun_report(*self.SLC, self.at('2026-12-21', '12:00'))
        self.close(winter['sunrise'], '07:48')
        self.close(winter['sunset'], '17:03')

    def test_next_event_follows_the_clock(self):
        morning = sky.sun_report(*self.SLC, self.at('2026-10-08', '05:00'))
        afternoon = sky.sun_report(*self.SLC, self.at('2026-10-08', '15:00'))
        night = sky.sun_report(*self.SLC, self.at('2026-10-08', '22:00'))
        self.assertEqual((morning['next'], morning['next_at']), ('sunrise', morning['sunrise']))
        self.assertEqual((afternoon['next'], afternoon['next_at']), ('sunset', afternoon['sunset']))
        self.assertEqual(night['next'], 'sunrise')
        self.assertIn("Tomorrow's sunrise", night['tooltip'])
        self.assertLess(afternoon['golden_hour'], afternoon['sunset'])


class Standalone(unittest.TestCase):
    def test_kp_rows_keep_a_day_back(self):
        now = datetime(2026, 10, 9, 18, tzinfo=sky.timezone.utc)
        rows = [{'time_tag': '2026-10-08T15:00:00', 'kp': 2, 'observed': 'observed', 'noaa_scale': None},
                {'time_tag': '2026-10-08T18:00:00', 'kp': 3.33, 'observed': 'observed', 'noaa_scale': None},
                {'time_tag': '2026-10-11T03:00:00', 'kp': 5.67, 'observed': 'predicted', 'noaa_scale': 'G2'}]
        self.assertEqual([r['time'] for r in sky.kp_rows(rows, now)], ['2026-10-08T18:00:00', '2026-10-11T03:00:00'])

    def test_location_from_omarchy_weather(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            sky.OMARCHY_WEATHER = Path(d) / 'weather.json'
            self.assertIsNone(sky.read_location())
            sky.OMARCHY_WEATHER.write_text('{"name": "Moab", "latitude": 38.57, "longitude": -109.55}')
            self.assertEqual(sky.read_location(), (38.57, -109.55))
            sky.OMARCHY_WEATHER.write_text('{"name": "Moab"}')
            self.assertIsNone(sky.read_location())

    def test_aurora_threshold_is_configurable(self):
        lat, lon = 64.84, -147.72  # Fairbanks
        evening = datetime(2026, 10, 9, 18, tzinfo=sky.timezone.utc)
        kp = [{'time': (evening + timedelta(hours=h)).strftime('%Y-%m-%dT%H:%M:%S'), 'kp': 3.33,
               'observed': 'predicted', 'scale': None} for h in range(0, 30, 3)]
        report = lambda: sky.tonight(lat, lon, date(2026, 10, 9), 'America/Anchorage')
        self.assertFalse(sky.bar_output(report(), None, lat, lon, None, kp)['text'].endswith(sky.AURORA_GLYPH))
        self.assertTrue(sky.bar_output(report(), None, lat, lon, None, kp, 3)['text'].endswith(sky.AURORA_GLYPH))

    def test_southern_hemisphere(self):
        out = sky.bar_output(sky.tonight(-33.87, 151.21, date(2026, 10, 9), 'Australia/Sydney'), None, -33.87, 151.21)
        self.assertTrue(out['panel']['south'])
        self.assertGreater(out['panel']['timeline']['core_best']['alt'], 40)


if __name__ == '__main__':
    unittest.main()
