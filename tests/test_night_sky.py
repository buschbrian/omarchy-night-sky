"""Offline checks for night-sky. tests/golden/night-report.json comes from
github.com/buschbrian/dark-sky-shot-planner (shared/golden, MIT), generated with astronomy-engine."""
from datetime import date, datetime, timedelta
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch
import tempfile
import io
from contextlib import redirect_stdout

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

    def test_timeline_cursor_clocks_use_location_zone_and_cover_endpoints(self):
        zone = sky.ZoneInfo('Australia/Sydney')
        report = sky.tonight(-33.87, 151.21, date(2026, 10, 20), 'Australia/Sydney')
        line = sky.bar_output(report, None, -33.87, 151.21)['panel']['timeline']
        self.assertEqual(len(line['times']), len(line['curves']['sun']))
        for edge, key in ((0, 'start_ms'), (-1, 'end_ms')):
            expected = datetime.fromtimestamp(line[key] / 1000, zone).strftime('%H:%M')
            self.assertEqual(line['times'][edge], expected)
        for curve in line['curves'].values():
            self.assertEqual(curve[0][0], 0)
            self.assertEqual(curve[-1][0], 1)

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


class Planner(unittest.TestCase):
    """The features brought over from dark-sky-shot-planner."""
    SLC = (40.76, -111.89)
    TZ = 'America/Denver'

    def night(self, day=date(2026, 10, 20)):
        report = sky.tonight(*self.SLC, day, self.TZ)
        return report, report['_plan']

    def hours(self, plan, **values):
        a = plan['darkness'][0].replace(minute=0, second=0, microsecond=0) - timedelta(hours=1)
        base = {'total': 5, 'low': 0, 'mid': 0, 'high': 5, 'gust': 10, 'temp': 10, 'dew': 0, 'jet': 40, 'aod': 0.05}
        return [dict(base, time=(a + timedelta(hours=h)).strftime('%Y-%m-%dT%H:%M'), **values) for h in range(14)]

    def test_rate_follows_the_thresholds_file(self):
        spec = sky.thresholds()['cloud_cover_total']
        self.assertEqual([sky.rate(v, spec) for v in (10, 40, 80, None)], ['good', 'marginal', 'poor', 'unavailable'])
        self.assertEqual(sky.rate(1.0, sky.thresholds()['dew_point_spread']), 'poor')

    def test_verdict_names_the_worst_gating_factor(self):
        report, plan = sky.tonight(*self.SLC, date(2026, 10, 9), self.TZ), None
        plan = report['_plan']
        clear = sky.shoot_verdict(plan, report, *self.SLC, self.hours(plan))
        self.assertEqual(clear['level'], 'go')
        windy = sky.shoot_verdict(plan, report, *self.SLC, self.hours(plan, gust=55))
        self.assertEqual((windy['level'], windy['headline']), ('no-go', 'No-go · gusts 55 km/h'))
        dewy = sky.shoot_verdict(plan, report, *self.SLC, self.hours(plan, dew=9.5))
        self.assertEqual(dewy['level'], 'go')  # dew is an advisory, never a gate

    def test_missing_or_stale_data_caps_at_marginal(self):
        report = sky.tonight(*self.SLC, date(2026, 10, 9), self.TZ)
        plan = report['_plan']
        no_aod = sky.shoot_verdict(plan, report, *self.SLC, self.hours(plan, aod=None))
        self.assertEqual((no_aod['level'], no_aod['incomplete']), ('marginal', True))
        now = datetime(2026, 10, 9, 18, tzinfo=sky.timezone.utc)
        stale = sky.shoot_verdict(plan, report, *self.SLC, self.hours(plan), (now - timedelta(hours=7)).isoformat(),
                                  now=now)
        self.assertEqual(stale['level'], 'marginal')
        self.assertEqual(sky.shoot_verdict(plan, report, *self.SLC, None)['level'], 'marginal')

    def test_aurora_never_lowers_the_verdict(self):
        report = sky.tonight(*self.SLC, date(2026, 10, 9), self.TZ)
        plan = report['_plan']
        v = sky.shoot_verdict(plan, report, *self.SLC, self.hours(plan), kp_max=7)
        self.assertEqual((v['level'], v['aurora']), ('go', True))

    def test_bright_moon_is_a_no_go(self):
        report = sky.tonight(*self.SLC, date(2026, 10, 25), self.TZ)
        v = sky.shoot_verdict(report['_plan'], report, *self.SLC, self.hours(report['_plan']))
        self.assertEqual(v['level'], 'no-go')
        self.assertTrue(v['headline'].startswith('No-go · moon'))

    def test_week_has_seven_nights(self):
        report, plan = self.night()
        days = sky.week(*self.SLC, date(2026, 10, 20), None, None, self.TZ)
        self.assertEqual([d['date'] for d in days][::6], ['2026-10-20', '2026-10-26'])
        self.assertTrue(all(d['level'] in ('marginal', 'no-go') for d in days))  # no conditions data

    def test_core_rises_southeast_and_sets_southwest(self):
        report, plan = self.night(date(2026, 6, 15))
        t = sky.core_times(plan, *self.SLC)
        self.assertTrue(110 < t['rise']['az'] < 150 and 210 < t['set']['az'] < 250)
        self.assertAlmostEqual(t['transit']['az'], 180, delta=3)
        self.assertAlmostEqual(t['transit']['alt'], 90 - 40.76 - 29.0, delta=1)

    def test_moon_phases_and_equinox_match_published_times(self):
        events = sky.sky_events(*self.SLC, date(2026, 9, 15), self.TZ, [], days=45)
        at = {e['title']: datetime.fromisoformat(e['at']) for e in events}
        utc = lambda text: datetime.fromisoformat(text).replace(tzinfo=sky.timezone.utc)
        # USNO: September equinox 2026-09-23 00:05 UT; new moon 2026-10-10 15:50 UT; full moon 2026-10-26 04:12 UT
        for title, want in [('September equinox', '2026-09-23T00:05'), ('New moon', '2026-10-10T15:50'),
                            ('Full moon', '2026-10-26T04:12')]:
            got = [t for k, t in at.items() if k == title][0] if title != 'New moon' else \
                [datetime.fromisoformat(e['at']) for e in events if e['title'] == 'New moon'][-1]
            self.assertLess(abs((got - utc(want)).total_seconds()), 20 * 60, title)

    def test_showers_are_judged_here(self):
        curated = sky.load_bundled_curated()
        events = sky.sky_events(*self.SLC, date(2026, 10, 15), self.TZ, curated)
        orionids = next(e for e in events if e['title'].startswith('Orionids'))
        self.assertIn('moon 8', orionids['detail'])  # an 80-something-percent moon at the 21 Oct peak
        self.assertIn('better', orionids['detail'])
        south = sky.sky_events(-33.87, 151.21, date(2026, 10, 15), 'Australia/Sydney', curated)
        self.assertTrue(any(e['title'].startswith('Orionids') for e in south))

    def test_precession_moves_ra_forward(self):
        ra, dec = sky.precess(0.0, 0.0, datetime(2026, 1, 1, tzinfo=sky.timezone.utc))
        self.assertAlmostEqual(ra, 26 * 3.075 * 15 / 3600, delta=0.02)
        self.assertAlmostEqual(dec, 26 * 20.04 / 3600, delta=0.02)

    def test_exposure(self):
        out = sky.exposure(20, 1.8, 5.9)
        self.assertEqual(out['rule500'], 25.0)
        self.assertAlmostEqual(out['npf'], 6.5, delta=0.1)
        self.assertEqual(sky.exposure(24, None, None, 1.5), {'focal': 24, 'aperture': None, 'rule500': 13.9})
        self.assertIsNone(sky.exposure(None))


class PhotographyPlanning(unittest.TestCase):
    SLC = (40.76, -111.89)
    TZ = 'America/Denver'

    def setUp(self):
        self.now = datetime(2026, 10, 20, 18, tzinfo=sky.timezone.utc)
        self.report = sky.tonight(*self.SLC, date(2026, 10, 20), self.TZ)
        self.plan = self.report['_plan']
        self.fetched = {k: self.now.isoformat() for k in ('clouds', 'haze', 'kp')}
        self.start = datetime(2026, 10, 21, 0, tzinfo=sky.timezone.utc)
        self.end = self.start + timedelta(hours=5)
        self.hours = [dict(time=(self.start + timedelta(hours=h)).strftime('%Y-%m-%dT%H:%M'),
                           total=5, aod=0.05, gust=10, temp=10, dew=0, jet=40) for h in range(5)]

    def best(self, hours=None, mode='meteors', kp=None):
        with patch.object(sky, 'target_windows', return_value=([(self.start, self.end)], 'Test target')):
            return sky.best_window(self.plan, self.report, *self.SLC, self.hours if hours is None else hours,
                                   self.fetched, kp, mode, [], 6, self.now)

    def test_short_clear_interval_beats_long_marginal_interval(self):
        hours = [dict(h, total=40) for h in self.hours]
        hours[2]['total'] = 5
        best = self.best(hours)
        self.assertEqual(best['level'], 'go')
        self.assertEqual(best['minutes'], 60)
        self.assertEqual(datetime.fromisoformat(best['start']), self.start + timedelta(hours=2))
        # Whole target-window assessment stays marginal; the clear hour is a separate opportunity.
        whole = sky.shoot_verdict(self.plan, self.report, *self.SLC, hours, self.fetched,
                                  mode='meteors', windows=[(self.start, self.end)], now=self.now)
        self.assertEqual(whole['level'], 'marginal')

    def test_complete_marginal_window_beats_longer_unknown_window(self):
        self.start += timedelta(minutes=15)
        best = self.best(self.hours[:1])
        self.assertEqual(best['minutes'], 45)
        self.assertEqual(best['level'], 'marginal')
        self.assertFalse(best['incomplete'])

    def test_cloudy_evening_does_not_erase_later_clear_window(self):
        hours = [dict(h, total=95 if i < 2 else 5) for i, h in enumerate(self.hours)]
        best = self.best(hours)
        self.assertEqual(best['level'], 'go')
        self.assertEqual(best['minutes'], 180)
        self.assertEqual(datetime.fromisoformat(best['start']), self.start + timedelta(hours=2))

    def test_partial_coverage_and_stale_haze_cannot_be_go(self):
        hours = self.hours[:2] + self.hours[3:]
        result = sky.shoot_verdict(self.plan, self.report, *self.SLC, hours, self.fetched,
                                   mode='meteors', windows=[(self.start, self.end)], now=self.now)
        self.assertEqual(result['level'], 'marginal')
        self.assertTrue(result['incomplete'])
        self.fetched['haze'] = (self.now - timedelta(hours=7)).isoformat()
        best = self.best()
        self.assertEqual(best['level'], 'marginal')
        self.assertTrue(best['stale'])
        self.fetched['haze'] = None
        self.assertTrue(self.best()['stale'])

    def test_missing_weather_is_a_provisional_window(self):
        best = self.best([])
        self.assertEqual(best['level'], 'marginal')
        self.assertTrue(best['incomplete'])

    def test_best_interval_never_recommends_elapsed_time(self):
        self.now = self.start + timedelta(hours=3, minutes=30)
        self.fetched = {k: self.now.isoformat() for k in self.fetched}
        best = self.best()
        self.assertGreaterEqual(datetime.fromisoformat(best['start']), self.now)
        self.now = self.end
        self.assertIsNone(self.best())

    def test_aurora_window_requires_overlapping_kp_and_checks_freshness(self):
        self.assertIsNone(self.best(mode='aurora'))
        kp = [{'time': self.start.strftime('%Y-%m-%dT%H:%M:%S'), 'kp': 7}]
        best = self.best(mode='aurora', kp=kp)
        self.assertEqual(best['minutes'], 180)
        self.assertEqual(best['direction'], 'N')
        self.fetched['kp'] = (self.now - timedelta(hours=7)).isoformat()
        self.assertTrue(self.best(mode='aurora', kp=kp)['stale'])
        self.assertEqual(self.best(mode='aurora', kp=kp)['level'], 'marginal')

    def test_bright_moon_is_useful_for_moonlit_mode(self):
        report = sky.tonight(*self.SLC, date(2026, 10, 25), self.TZ)
        plan = report['_plan']
        windows, subject = sky.target_windows(plan, *self.SLC, 'moonlit')
        self.assertTrue(windows)
        self.assertEqual(sky.target_windows(plan, *self.SLC, 'milky-way')[0], [])
        for a, b in windows:
            mid = a + (b - a) / 2
            self.assertGreater(sky.moon_rise_set_margin(mid, *self.SLC), 0)
            self.assertLessEqual(sky.sun_altitude(mid, *self.SLC), -6)
        self.assertEqual(sky.target_windows(plan, *self.SLC, 'aurora')[0], [plan['darkness']])

    def test_meteor_mode_uses_active_radiant_in_moon_free_dark(self):
        showers = sky.load_bundled_curated()
        windows, subject = sky.target_windows(self.plan, *self.SLC, 'meteors', showers)
        self.assertIn('Orionids', subject)
        self.assertTrue(windows)
        for a, b in windows:
            self.assertTrue(any(free[0] <= a < b <= free[1] for free in self.plan['moon_free']))
        self.assertEqual(sky.target_windows(self.plan, *self.SLC, 'meteors', [])[0], [])

    def test_week_recommendation_needs_complete_fresh_forecast(self):
        days = sky.week(*self.SLC, date(2026, 10, 20), None, None, self.TZ,
                        mode='meteors', curated=sky.load_bundled_curated(), now=self.now)
        self.assertFalse(any(n['recommended'] for n in days))
        # Cover each target night; lowest clouds and lighter gusts are visible in the chosen interval's factors.
        start = self.plan['darkness'][0].replace(minute=0, second=0, microsecond=0) - timedelta(hours=1)
        hours = [dict(self.hours[0], time=(start + timedelta(hours=h)).strftime('%Y-%m-%dT%H:%M')) for h in range(180)]
        days = sky.week(*self.SLC, date(2026, 10, 20), hours, self.fetched, self.TZ,
                        mode='meteors', curated=sky.load_bundled_curated(), now=self.now)
        chosen = [n for n in days if n['recommended']]
        self.assertEqual(len(chosen), 1)
        self.assertFalse(chosen[0]['best_window']['incomplete'])
        self.assertFalse(chosen[0]['best_window']['stale'])

    def test_forecast_sources_keep_independent_timestamps_and_null_hours(self):
        with patch.object(sky, 'cached_json', side_effect=[([dict(self.hours[0], total=None)], '2026-10-20T18:00:00+00:00'),
                                                         ({self.hours[0]['time']: 0.2}, '2026-10-20T08:00:00+00:00')]):
            hours, fetched = sky.load_conditions(*self.SLC, now=self.now)
        self.assertEqual(len(hours), 1)
        self.assertIsNone(hours[0]['total'])
        self.assertNotEqual(fetched['clouds'], fetched['haze'])
        out = sky.bar_output(self.report, lat=self.SLC[0], lon=self.SLC[1], clouds=hours, fetched=fetched,
                             now=self.now, mode='meteors', curated=sky.load_bundled_curated(), extras=False)
        self.assertTrue(out['panel']['sources']['haze']['stale'])
        self.assertFalse(out['panel']['sources']['clouds']['stale'])


class SavedLocations(unittest.TestCase):
    def run_cli(self, args):
        out = io.StringIO()
        with redirect_stdout(out):
            sky.main(args)
        return json.loads(out.getvalue())

    def test_save_replace_remove_and_private_file(self):
        with tempfile.TemporaryDirectory() as d, patch.object(sky, 'LOCATIONS', Path(d) / 'places.json'):
            args = ['--save-location', 'Test place', '--lat', '40', '--lon', '-111', '--tz', 'America/Denver']
            self.run_cli(args)
            self.assertEqual(sky.LOCATIONS.stat().st_mode & 0o777, 0o600)
            self.assertEqual(self.run_cli(['--list-locations'])[0]['lat'], 40)
            args[3] = '41'
            self.run_cli(args)
            self.assertEqual(len(sky.saved_places()), 1)
            self.assertEqual(sky.saved_places()[0]['lat'], 41)
            self.run_cli(['--remove-location', 'Test place'])
            self.assertEqual(sky.saved_places(), [])

    def test_invalid_coordinates_or_timezone_do_not_overwrite(self):
        with tempfile.TemporaryDirectory() as d, patch.object(sky, 'LOCATIONS', Path(d) / 'places.json'):
            for coords, tz in [(('91', '0'), 'America/Denver'), (('40', '0'), 'Not/AZone')]:
                reply = self.run_cli(['--save-location', 'Bad', '--lat', coords[0], '--lon', coords[1], '--tz', tz])
                self.assertIn('error', reply)
            self.assertFalse(sky.LOCATIONS.exists())

    def test_compare_uses_each_locations_timezone_and_selected_mode(self):
        with tempfile.TemporaryDirectory() as d, patch.object(sky, 'LOCATIONS', Path(d) / 'places.json'):
            sky.write_places([sky.validate_place('Test south', -33.87, 151.21, 'Australia/Sydney')])
            out = self.run_cli(['--compare-locations', '--date', '2026-12-21', '--lat', '40.76', '--lon', '-111.89',
                                '--tz', 'America/Denver', '--mode', 'moonlit', '--offline'])
            self.assertEqual([p['location']['tz'] for p in out['comparison']], ['America/Denver', 'Australia/Sydney'])
            self.assertTrue(all(p['date'] == '2026-12-21' for p in out['comparison']))
            self.assertFalse(any(p['shoot']['level'] == 'go' for p in out['comparison']))


if __name__ == '__main__':
    unittest.main()
