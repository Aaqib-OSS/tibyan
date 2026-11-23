import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tibyan/features/tasbih/presentation/styles/misbaha_view.dart';
import 'package:tibyan/features/tasbih/tasbih_settings.dart';

const _size = Size(300, 600);

/// The misbaha alone, its count kept here as the counter would.
class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.render,
    required this.animate,
    this.roundSize,
    this.start = 0,
    this.counted,
  });

  final MisbahaRender? render;
  final bool animate;
  final int? roundSize;
  final int start;
  final ValueNotifier<int>? counted;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int count = widget.start;
  int counts = 0;

  /// A count made elsewhere (the volume buttons).
  void external() => setState(() => count = _next(count));

  int _next(int c) {
    final t = widget.roundSize;
    return t != null && c + 1 >= t ? 0 : c + 1;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Center(
      child: SizedBox.fromSize(
        size: _size,
        child: MisbahaView(
          material: BeadMaterial.amber,
          render: widget.render,
          animate: widget.animate,
          count: count,
          roundSize: widget.roundSize,
          onCount: () => setState(() {
            counts++;
            widget.counted?.value = counts;
            count = _next(count);
          }),
        ),
      ),
    ),
  );
}

double _phase(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(MisbahaView),
      matching: find.byType(CustomPaint),
    ),
  );
  return switch (paint.painter) {
    final SuggestedMisbahaPainter p => p.motion.phase,
    final RealMisbahaPainter p => p.motion.phase,
    _ => throw StateError('no misbaha painter'),
  };
}

TerminalBead _terminal(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(MisbahaView),
      matching: find.byType(CustomPaint),
    ),
  );
  return (paint.painter! as SuggestedMisbahaPainter).terminal;
}

/// Frames enough for an animation to run its course (its first frame only
/// starts its clock).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

CustomPainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find.descendant(
        of: find.byType(MisbahaView),
        matching: find.byType(CustomPaint),
      ),
    )
    .painter!;

void main() {
  // As where fragment shaders work (the pieces are drawn as shaded discs:
  // no program is loaded in a test).
  setUp(() => BeadShader.debugSetAvailable(true));
  tearDown(() => BeadShader.debugSetAvailable(null));

  group('which look is drawn', () {
    testWidgets('true 3D for a reader who never chose', (tester) async {
      await tester.pumpWidget(const _Host(render: null, animate: true));
      expect(_painter(tester), isA<RealMisbahaPainter>());
    });

    testWidgets('the reader\'s own choice is kept', (tester) async {
      await tester.pumpWidget(
        const _Host(render: MisbahaRender.suggested, animate: true),
      );
      expect(_painter(tester), isA<SuggestedMisbahaPainter>());
    });

    testWidgets('the suggested look where shaders are unavailable', (
      tester,
    ) async {
      BeadShader.debugSetAvailable(false);
      for (final chosen in [null, MisbahaRender.real]) {
        await tester.pumpWidget(_Host(render: chosen, animate: true));
        expect(_painter(tester), isA<SuggestedMisbahaPainter>());
        await tester.tap(find.byType(MisbahaView));
        await _settle(tester);
        expect(_phase(tester), 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('it falls back when the shader turns out not to load', (
      tester,
    ) async {
      BeadShader.debugSetAvailable(null);
      await tester.pumpWidget(
        const _Host(render: null, animate: true, start: 7),
      );
      // Not known yet: the 3D scene, with nothing drawn.
      expect((_painter(tester) as RealMisbahaPainter).blank, isTrue);
      BeadShader.available.value = false;
      await tester.pump();
      expect(_painter(tester), isA<SuggestedMisbahaPainter>());
      await tester.tap(find.byType(MisbahaView));
      await _settle(tester);
      expect(_phase(tester), 1);
    });
  });

  testWidgets('true 3D: the joint crosses after the 33rd bead, and tells', (
    tester,
  ) async {
    var laps = 0;
    var count = 31;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, set) => MisbahaView(
            material: BeadMaterial.rosewood,
            render: MisbahaRender.real,
            count: count,
            roundSize: 100,
            onLap: () => laps++,
            onCount: () => set(() => count++),
          ),
        ),
      ),
    );
    final motion = (_painter(tester) as RealMisbahaPainter).motion;
    expect(motion.step, 31);
    await tester.tap(find.byType(MisbahaView));
    await _settle(tester);
    expect((laps, motion.jointDue), (0, false));
    await tester.tap(find.byType(MisbahaView));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(motion.jointCrossing, isTrue);
    // A tap while it crosses is counted, and its bead follows.
    await tester.tap(find.byType(MisbahaView));
    expect(count, 34);
    for (var i = 0; i < 6; i++) {
      await _settle(tester);
    }
    expect((laps, motion.done, motion.step), (1, 3, 31 + 3 + 1));
    // At rest nothing asks for frames.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('true 3D paints each material, with and without a count', (
    tester,
  ) async {
    for (final m in BeadMaterial.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: MisbahaView(
            key: ValueKey(m),
            material: m,
            render: MisbahaRender.real,
            count: 20,
            roundSize: 33,
            onCount: () {},
          ),
        ),
      );
      await tester.tap(find.byType(MisbahaView));
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.takeException(), isNull);
      await _settle(tester);
    }
  });

  testWidgets('true 3D: a sideways drag carries the bead either way', (
    tester,
  ) async {
    for (final dx in [-1.0, 1.0]) {
      final counted = ValueNotifier(0);
      await tester.pumpWidget(
        _Host(
          key: ValueKey(dx),
          render: MisbahaRender.real,
          animate: true,
          counted: counted,
        ),
      );
      final travel = RealMisbahaPainter.travel(_size);
      await tester.timedDrag(
        find.byType(MisbahaView),
        Offset(dx * (20 + travel * .7), 0),
        const Duration(milliseconds: 500),
      );
      await _settle(tester);
      expect(counted.value, 1);
      expect(_phase(tester), 1);
    }
  });

  for (final render in MisbahaRender.values) {
    group(render.name, () {
      double travel() => render == MisbahaRender.real
          ? RealMisbahaPainter.travel(_size)
          : SuggestedMisbahaPainter.travel(_size);

      testWidgets('a tap moves the whole string one bead and counts', (
        tester,
      ) async {
        final counted = ValueNotifier(0);
        await tester.pumpWidget(
          _Host(render: render, animate: true, counted: counted),
        );
        await tester.tap(find.byType(MisbahaView));
        await tester.pump();
        expect(counted.value, 1);
        // On its way, then at rest one bead on: never back where it was.
        await tester.pump(const Duration(milliseconds: 60));
        expect(_phase(tester), greaterThan(0));
        await tester.pump(const Duration(milliseconds: 300));
        expect(_phase(tester), 1);
      });

      testWidgets('a pull short of 40% eases back and does not count', (
        tester,
      ) async {
        final counted = ValueNotifier(0);
        await tester.pumpWidget(
          _Host(render: render, animate: true, counted: counted),
        );
        final g = await tester.startGesture(
          tester.getCenter(find.byType(MisbahaView)),
        );
        // Past the slop, then to 30% of the way, slowly.
        for (var i = 0; i < 10; i++) {
          await g.moveBy(Offset(0, (20 + travel() * .3) / 10));
          await tester.pump(const Duration(milliseconds: 40));
        }
        expect(_phase(tester), inExclusiveRange(0, .4));
        await tester.pump(const Duration(milliseconds: 200));
        await g.up();
        await _settle(tester);
        expect(counted.value, 0);
        expect(_phase(tester), 0);
      });

      testWidgets('a pull past 40% goes over on release and counts', (
        tester,
      ) async {
        final counted = ValueNotifier(0);
        await tester.pumpWidget(
          _Host(render: render, animate: true, counted: counted),
        );
        final g = await tester.startGesture(
          tester.getCenter(find.byType(MisbahaView)),
        );
        for (var i = 0; i < 10; i++) {
          await g.moveBy(Offset(0, (20 + travel() * .55) / 10));
          await tester.pump(const Duration(milliseconds: 40));
        }
        await tester.pump(const Duration(milliseconds: 200));
        await g.up();
        await _settle(tester);
        expect(counted.value, 1);
        expect(_phase(tester), 1);
      });

      for (final (beads, counts) in [(1.3, 1), (2.2, 1), (3.6, 3)]) {
        testWidgets('one drag of $beads beads counts $counts', (tester) async {
          final counted = ValueNotifier(0);
          await tester.pumpWidget(
            _Host(render: render, animate: true, counted: counted),
          );
          final g = await tester.startGesture(
            tester.getCenter(find.byType(MisbahaView)) - const Offset(0, 250),
          );
          // Past the slop first, then the pull itself, steadily.
          await g.moveBy(const Offset(0, 20));
          await tester.pump(const Duration(milliseconds: 16));
          final steps = (beads * 20).round();
          for (var i = 0; i < steps; i++) {
            await g.moveBy(Offset(0, travel() * beads / steps));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await tester.pump(const Duration(milliseconds: 300));
          await g.up();
          await _settle(tester);
          expect(counted.value, counts);
          expect(_phase(tester), counts);
        });
      }

      testWidgets('fast taps queue and none is lost', (tester) async {
        final counted = ValueNotifier(0);
        await tester.pumpWidget(
          _Host(render: render, animate: true, counted: counted),
        );
        for (var i = 0; i < 12; i++) {
          await tester.tap(find.byType(MisbahaView));
          await tester.pump(const Duration(milliseconds: 30));
        }
        expect(counted.value, 12);
        await _settle(tester);
        expect(_phase(tester), 12);
      });

      testWidgets('reduce motion moves the string at once', (tester) async {
        await tester.pumpWidget(_Host(render: render, animate: false));
        await tester.tap(find.byType(MisbahaView));
        await tester.pump();
        expect(_phase(tester), 1);
      });

      testWidgets('counts made elsewhere move the string too', (tester) async {
        final counted = ValueNotifier(0);
        await tester.pumpWidget(
          _Host(render: render, animate: true, counted: counted),
        );
        final host = tester.state<_HostState>(find.byType(_Host));
        host
          ..external()
          ..external();
        await tester.pump();
        host.external();
        await _settle(tester);
        await _settle(tester);
        expect(_phase(tester), 3);
        expect(counted.value, 0);
      });

      testWidgets(
        'the terminal bead closes each round',
        skip: render == MisbahaRender.real,
        (tester) async {
          await tester.pumpWidget(
            _Host(render: render, animate: true, roundSize: 33, start: 31),
          );
          final terminal = _terminal(tester);
          // Count 31 of 33: the bead after the one at the gap ends the round,
          // and so does every 33rd after it.
          expect(terminal(0), isFalse);
          expect(terminal(1), isTrue);
          expect(terminal(34), isTrue);
          expect(terminal(2), isFalse);
        },
      );
    });
  }
}
