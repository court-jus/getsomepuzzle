import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/play_model.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/readiness.dart';

/// One play whose duration is [r] × the model's expected duration for its
/// puzzle. `r` is the mix-independent relative pace the readiness model
/// scores; rounding to whole seconds moves it by < 1 % on these fixtures.
ReadinessSample _play(
  double r, {
  required DateTime when,
  int cplx = 30,
  int cells = 20,
  int nCons = 3,
  int failures = 0,
  int gapMs = 0,
}) {
  final expected = expectedDuration(cplx, cells, failures, nCons);
  final duration = (expected * r).round();
  return ReadinessSample(
    finished: when,
    duration: duration < 1 ? 1 : duration,
    failures: failures,
    cplx: cplx,
    cells: cells,
    nCons: nCons,
    longestGapMs: gapMs,
  );
}

/// [n] plays at a steady relative pace [r], one minute apart.
List<ReadinessSample> _steady(
  int n,
  double r, {
  DateTime? start,
  int cplx = 30,
}) {
  final base = start ?? DateTime(2026, 6, 1);
  return List.generate(
    n,
    (i) => _play(
      r,
      when: base.add(Duration(minutes: i)),
      cplx: cplx,
    ),
  );
}

/// 39 plays is the minimum that yields `kSustainedPlays` (20) windows.
const int _minForVerdict = 39;

void main() {
  final now = DateTime(2026, 6, 2);
  const nextTierSeconds = 46.5; // 2-player reference

  group('evaluateReadinessSeries — window verdicts', () {
    test('promotes at a steady r = 1.2', () {
      final series = evaluateReadinessSeries(
        _steady(_minForVerdict, 1.2),
        nextTierSeconds,
        now: now,
      );
      expect(series, hasLength(kSustainedPlays));
      expect(series.every((w) => w.vote == ReadinessVote.promote), isTrue);
      expect(sustainedVote(series), ReadinessVote.promote);
      expect(series.first.medianR, closeTo(1.2, 0.05));
      expect(series.first.samples, kWindow);
    });

    test('holds at r = 1.65, inside the hysteresis band', () {
      final series = evaluateReadinessSeries(
        _steady(_minForVerdict, 1.65),
        nextTierSeconds,
        now: now,
      );
      expect(series.every((w) => w.vote == ReadinessVote.hold), isTrue);
      expect(sustainedVote(series), ReadinessVote.hold);
    });

    test('demotes at a steady r = 3.5 (past the strong-demote bound)', () {
      final series = evaluateReadinessSeries(
        _steady(_minForVerdict, 3.5),
        nextTierSeconds,
        now: now,
      );
      expect(series.every((w) => w.vote == ReadinessVote.demote), isTrue);
      expect(sustainedVote(series), ReadinessVote.demote);
    });

    test('demotes at r = 1.9 only when the hard-play share clears 20 %', () {
      // The AND clause: a uniformly slow player (no individual play at
      // 3 × expected) sits below kDemoteStrongR, so the demote needs
      // genuine struggle plays.
      final gentle = evaluateReadinessSeries(
        _steady(_minForVerdict, 1.9),
        nextTierSeconds,
        now: now,
      );
      expect(gentle.every((w) => w.vote == ReadinessVote.hold), isTrue);

      // Every 5th play runs at 3.5 × expected → 4 hard plays per 20-play
      // window (share 0.20) while the median stays at 1.9.
      final base = DateTime(2026, 6, 1);
      final struggling = List.generate(_minForVerdict, (i) {
        final r = i % 5 == 0 ? 3.5 : 1.9;
        return _play(r, when: base.add(Duration(minutes: i)));
      });
      final series = evaluateReadinessSeries(
        struggling,
        nextTierSeconds,
        now: now,
      );
      expect(series.first.hardShare, closeTo(kHardShareForDemote, 0.01));
      expect(series.every((w) => w.vote == ReadinessVote.demote), isTrue);
      expect(sustainedVote(series), ReadinessVote.demote);
    });
  });

  group('evaluateReadinessSeries — sustained rule', () {
    test('one deviating window among promoting ones does not promote', () {
      // 10 struggle plays sit at the oldest end; only the oldest window
      // (offset 19) sees them and reads hold, while the other 19 windows
      // promote. A single dissenting window must block the move.
      final base = DateTime(2026, 6, 1);
      final samples = [
        for (var i = 0; i < 10; i++)
          _play(2.5, when: base.add(Duration(minutes: i))),
        for (var i = 10; i < _minForVerdict; i++)
          _play(1.2, when: base.add(Duration(minutes: i))),
      ];
      final series = evaluateReadinessSeries(
        samples,
        nextTierSeconds,
        now: now,
      );
      expect(series, hasLength(kSustainedPlays));
      expect(series.last.vote, ReadinessVote.hold);
      expect(sustainedVote(series), ReadinessVote.hold);
    });

    test('fewer than 39 usable plays of the tier is never a fire', () {
      final series = evaluateReadinessSeries(
        _steady(_minForVerdict - 1, 1.2),
        nextTierSeconds,
        now: now,
      );
      expect(series.length, lessThan(kSustainedPlays));
      expect(sustainedVote(series), ReadinessVote.unknown);
    });

    test('no usable plays at all is unknown', () {
      expect(
        sustainedVote(
          evaluateReadinessSeries(const [], nextTierSeconds, now: now),
        ),
        ReadinessVote.unknown,
      );
    });
  });

  group('evaluateReadinessSeries — sample hygiene', () {
    test('AFK outlier is trimmed and does not move the median', () {
      final samples = _steady(_minForVerdict, 1.2);
      // One play left open for 40 × the window median.
      samples[_minForVerdict - 1] = _play(40, when: samples.last.finished);
      final series = evaluateReadinessSeries(
        samples,
        nextTierSeconds,
        now: now,
      );
      expect(series.first.medianR, closeTo(1.2, 0.05));
      expect(series.first.vote, ReadinessVote.promote);
    });

    test('newest sample older than 14 days is unknown', () {
      final stale = _steady(_minForVerdict, 1.2, start: DateTime(2026, 5, 1));
      expect(
        evaluateReadinessSeries(stale, nextTierSeconds, now: now),
        isEmpty,
      );
    });

    test('gross-AFK gaps and cplx-free plays are dropped', () {
      final samples = _steady(_minForVerdict, 1.2);
      samples[_minForVerdict - 1] = _play(
        1.2,
        when: samples.last.finished,
        gapMs: kMaxGapMs + 1,
      );
      final first = evaluateReadinessSeries(
        samples,
        nextTierSeconds,
        now: now,
      ).first;
      // The dropped play is the newest one, so the newest window is still
      // full and unchanged.
      expect(first.samples, kWindow);
      expect(first.vote, ReadinessVote.promote);
    });

    test('the slope sanity bound is a no-op at n = 20', () {
      final base = DateTime(2026, 6, 1);
      final flat = List.generate(
        _minForVerdict,
        (i) => _play(1.2, when: base.add(Duration(minutes: i))),
      );
      expect(
        evaluateReadinessSeries(flat, nextTierSeconds, now: now).first.slope,
        0,
      );
    });
  });

  group('effort cap', () {
    test('blocks a promotion whose projection exceeds 90 s', () {
      // r = 1.2 is comfortably under kPromoteR, but the next tier's
      // reference puzzle would take 1.2 × 150 s.
      final series = evaluateReadinessSeries(
        _steady(_minForVerdict, 1.2),
        150,
        now: now,
      );
      expect(series.every((w) => w.vote == ReadinessVote.hold), isTrue);
    });

    test('allows a promotion whose projection fits', () {
      final series = evaluateReadinessSeries(
        _steady(_minForVerdict, 1.2),
        60,
        now: now,
      );
      expect(series.every((w) => w.vote == ReadinessVote.promote), isTrue);
      expect(series.first.projectedSeconds, lessThan(kEffortCapSeconds));
    });
  });

  group('tier reference table', () {
    test('every playable tier has a reference and mad has no successor', () {
      for (var tier = 0; tier < kTierReferencePuzzles.length; tier++) {
        expect(tierReferenceSeconds(tier), isNotNull);
      }
      expect(tierReferenceSeconds(kTierReferencePuzzles.length), isNull);
    });

    test('projects the documented effort for each tier', () {
      // Guards the table against an accidental edit: the values come from
      // the shipped catalogs' median (cplx, cells, nCons).
      expect(tierReferenceSeconds(0), closeTo(39, 2));
      expect(tierReferenceSeconds(1), closeTo(47, 2));
      expect(tierReferenceSeconds(5), closeTo(175, 2));
    });
  });

  group('model cplx clamp', () {
    test('a 500-cplx play scores exactly like a 120-cplx play', () {
      const cells = 24;
      const dur = 600;
      expect(
        playLevel(dur, 500, cells, 0, 6),
        playLevel(dur, kCplxModelMax, cells, 0, 6),
      );
      expect(
        expectedDuration(500, cells, 0, 6),
        expectedDuration(kCplxModelMax, cells, 0, 6),
      );
    });

    test('cplx at or below the cap is untouched', () {
      expect(
        expectedDuration(kCplxModelMax - 1, 24, 0, 6),
        lessThan(expectedDuration(kCplxModelMax, 24, 0, 6)),
      );
    });
  });
}
