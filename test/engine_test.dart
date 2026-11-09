import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gag_othello/core/engine.dart';

/// 盤面を 64 文字の文字列にする（'0' '1' '2'）
String _boardStr(List<int> b) => b.join();

void main() {
  group('基本ルール', () {
    test('初期配置の合法手は 19,26,37,44（左上から順）', () {
      final b = initialBoard();
      expect(legalMoves(b, 1).keys.toList(), <int>[19, 26, 37, 44]);
      expect(flipsFor(b, 19, 1), <int>[27]);
      expect(flipsFor(b, 0, 1), isEmpty);
    });

    test('pickMove は合法手を返し、打てないときは -1', () {
      final rng = math.Random(5);
      final game = Game(rng: rng);
      final mv = pickMove(game, 1, rng);
      expect(game.moves(1).containsKey(mv), isTrue);
      game.b = List<int>.filled(64, 0);
      expect(pickMove(game, 1, rng), -1);
    });
  });

  group('ストレスゲージ', () {
    List<int> centerOnly() {
      final b = List<int>.filled(64, 0);
      b[27] = 2;
      b[28] = 1;
      b[35] = 1;
      b[36] = 2;
      return b;
    }

    test('角を取ると相手に加算（reason=corner）', () {
      final game = Game(rng: math.Random(1));
      final b = centerOnly();
      b[1] = 2;
      b[2] = 1;
      game.b = b;
      final res = game.play(0);
      expect(res, isNotNull);
      expect(res!.corner, isTrue);
      expect(res.gauge.length, 1);
      expect(res.gauge.first.p, 2);
      expect(res.gauge.first.delta, GaugeCfg.corner);
      expect(res.gauge.first.reason, StressReason.corner);
      expect(game.gauge, <int>[0, GaugeCfg.corner]);
    });

    test('1手で5枚以上返すと相手に加算（reason=bigflip）', () {
      final game = Game(rng: math.Random(1));
      final b = centerOnly();
      b[0] = 1;
      for (var i = 1; i <= 5; i++) {
        b[i] = 2;
      }
      game.b = b;
      final res = game.play(6);
      expect(res, isNotNull);
      expect(res!.flips.length, 5);
      expect(res.corner, isFalse);
      expect(game.gauge, <int>[0, GaugeCfg.bigFlip]);
      expect(res.gauge.single.reason, StressReason.bigflip);
    });

    test('手動パス：待ち→パスで加算、続けてのパスはさらに多く', () {
      final game = Game(rng: math.Random(1), manualPass: true);
      final b = List<int>.filled(64, 0);
      // 1P だけが打てる「挟める形」を3か所。2P は打てる場所が一つもない。
      b[0] = 1;
      b[1] = 2; // 2 に置くと 1 が返る
      b[56] = 1;
      b[57] = 2; // 58
      b[7] = 1;
      b[15] = 2; // 23
      game.b = b;

      var res = game.play(2);
      expect(res, isNotNull);
      expect(res!.pending, 2);
      expect(game.pending, 2);
      expect(game.turn, 2);
      expect(game.pass(), isNotNull, reason: '待ち状態ならパスできる');
      expect(game.gauge, <int>[0, GaugeCfg.pass]);
      expect(game.turn, 1);
      expect(game.pending, 0);
      expect(game.pass(), isNull, reason: '待ちでなければパスできない');

      res = game.play(58);
      expect(res!.pending, 2);
      final pr = game.pass()!;
      expect(pr.kind, ResultKind.pass);
      expect(pr.passed, 2);
      expect(pr.gauge.single.delta, GaugeCfg.passStreak);
      expect(game.gauge, <int>[0, GaugeCfg.pass + GaugeCfg.passStreak]);

      res = game.play(23);
      expect(res!.over, isTrue);
      expect(game.over, isTrue);
    });

    test('自動パス（manualPass=false）は待たずに進む', () {
      final game = Game(rng: math.Random(1));
      final b = List<int>.filled(64, 0);
      b[0] = 1;
      b[1] = 2;
      b[56] = 1;
      b[57] = 2;
      game.b = b;
      final res = game.play(2);
      expect(res!.pending, 0);
      expect(res.passed, 2);
      expect(game.turn, 1);
      expect(game.gauge[1], GaugeCfg.pass);
    });
  });

  group('台パン', () {
    test('空き6以下は封印、7以上なら相手の手番でも使える', () {
      final game = Game(rng: math.Random(3));
      game.b = List<int>.generate(64, (int i) => i % 2 == 0 ? 1 : 2);
      game.gauge = <int>[100, 100];
      for (final i in <int>[10, 20, 30, 40, 50, 60]) {
        game.b[i] = 0;
      }
      expect(game.empties(), 6);
      expect(game.isHeat, isTrue);
      expect(game.canDaipan(1), isFalse);
      expect(game.daipan(1), isNull);

      game.b[62] = 0; // 空き7
      expect(game.isHeat, isFalse);
      expect(game.turn, 1);
      expect(game.canDaipan(2), isTrue, reason: '自分の番でなくても台パンできる');
      final res = game.daipan(2);
      expect(res, isNotNull);
      expect(res!.kind, ResultKind.daipan);
      expect(game.gauge[1], 0);
      expect(game.daipans, <int>[0, 1]);
      expect(game.gauge[0], 100, reason: '相手のゲージは減らない');
      if (res.tier < 4) {
        final c = game.counts();
        expect(c[0] + c[1], 57);
        expect(c[1], 29, reason: '端数は台パンした側');
        expect(c[0], 28);
      }
    });

    test('ゲージが足りなければ台パンできない', () {
      final game = Game(rng: math.Random(3));
      game.gauge = <int>[99, 0];
      expect(game.canDaipan(1), isFalse);
      expect(game.daipan(1), isNull);
    });

    test('daipanShuffle：占有マスは動かさず、同数（端数は台パン側）、角は1/2', () {
      final rng = math.Random(12345);
      var samples = 0;
      var tier1 = 0;
      var bad = 0;
      var cornerOcc = 0;
      var cornerToSlam = 0;
      final fails = <String>[];
      for (var g = 0; g < 600; g++) {
        final game = Game(rng: rng);
        final stopAt = 4 + rng.nextInt(56); // 4〜59手目で止める
        for (var k = 0; k < stopAt && !game.over; k++) {
          final mv = pickMove(game, game.turn, rng);
          if (mv < 0) break;
          game.play(mv);
        }
        if (game.over) continue;
        final e = game.empties();
        if (e < 5) continue;
        for (final slammer in <int>[1, 2]) {
          final before = List<int>.of(game.b);
          final total = 64 - e;
          final target = (total + 1) ~/ 2;
          final r = daipanShuffle(game.b, slammer, game.turn, rng);
          expect(_boardStr(game.b), _boardStr(before), reason: '元の盤面は書き換えない');
          samples++;
          if (r.tier == 1) tier1++;
          final nb = r.board;
          var c1 = 0;
          var c2 = 0;
          var ok = true;
          for (var i = 0; i < 64; i++) {
            if ((before[i] == 0) != (nb[i] == 0)) ok = false;
            if (nb[i] == 1) c1++;
            if (nb[i] == 2) c2++;
          }
          final cs = slammer == 1 ? c1 : c2;
          final co = slammer == 1 ? c2 : c1;
          if (r.tier < 4 && (cs != target || co != total - target)) ok = false;
          if (r.tier == 1 && !(hasMove(nb, game.turn) && hasMove(nb, 3 - game.turn))) ok = false;
          if (r.tier == 2 && !hasMove(nb, game.turn)) ok = false;
          for (final c in <int>[0, 7, 56, 63]) {
            if (before[c] != 0) {
              cornerOcc++;
              if (nb[c] == slammer) cornerToSlam++;
            }
          }
          if (!ok) {
            bad++;
            if (fails.length < 3) fails.add('e=$e slammer=$slammer tier=${r.tier} c1=$c1 c2=$c2');
          }
        }
      }
      expect(samples, greaterThan(300));
      expect(bad, 0, reason: fails.join(' / '));
      expect(tier1 / samples, greaterThan(0.9), reason: '両者に合法手が残る盤面にほぼ必ず落ち着く');
      expect(cornerOcc, greaterThan(200));
      final rate = cornerToSlam / cornerOcc;
      expect(rate, inInclusiveRange(0.40, 0.60), reason: '占有済みの角は 1/2 で台パン側');
    });
  });

  group('ブラウザ試作版との照合（golden）', () {
    test('決まった対局を再生すると、1手ごとに JS 版と同じ結果になる', () {
      final raw = jsonDecode(File('test/golden/golden_games.json').readAsStringSync()) as Map<String, dynamic>;
      final games = raw['games'] as List<dynamic>;
      expect(games, isNotEmpty);
      var steps = 0;
      for (final gj in games) {
        final gm = gj as Map<String, dynamic>;
        final game = Game(rng: math.Random(1), manualPass: true);
        final list = gm['steps'] as List<dynamic>;
        for (var n = 0; n < list.length; n++) {
          final st = list[n] as Map<String, dynamic>;
          final where = 'seed ${gm['seed']} step $n';
          final a = st['a'] as int;
          final TurnResult? res = a == -1 ? game.pass() : game.play(a);
          expect(res, isNotNull, reason: '$where: 手が受理される');
          final r = res!;
          if (a >= 0) {
            expect(jsonEncode(r.flips), jsonEncode(st['flips']), reason: '$where flips');
          }
          final gauge = r.gauge.map<List<Object>>((GaugeEvent e) => <Object>[e.p, e.delta, e.reason.name]).toList();
          expect(jsonEncode(gauge), jsonEncode(st['gauge']), reason: '$where gauge events');
          expect(r.passed, st['passed'], reason: '$where passed');
          expect(r.pending, st['pending'], reason: '$where pending');
          expect(r.heatStarted, st['heatStarted'], reason: '$where heatStarted');
          expect(r.over, st['over'], reason: '$where over');
          expect(r.corner, st['corner'], reason: '$where corner');
          expect(game.turn, st['turn'], reason: '$where turn');
          expect(jsonEncode(game.gauge), jsonEncode(st['g']), reason: '$where gauge');
          expect(jsonEncode(game.passStreak), jsonEncode(st['streak']), reason: '$where passStreak');
          expect(jsonEncode(game.maxHits), jsonEncode(st['hits']), reason: '$where maxHits');
          expect(jsonEncode(game.counts()), jsonEncode(st['counts']), reason: '$where counts');
          expect(game.empties(), st['empties'], reason: '$where empties');
          expect(_boardStr(game.b), st['board'], reason: '$where board');
          if (!game.over && game.pending == 0) {
            expect(jsonEncode(game.moves().keys.toList()), jsonEncode(st['legal']), reason: '$where legal moves');
          }
          final can = st['canDaipan'] as List<dynamic>;
          expect(game.canDaipan(1), can[0], reason: '$where canDaipan(1)');
          expect(game.canDaipan(2), can[1], reason: '$where canDaipan(2)');
          steps++;
        }
        expect(game.over, isTrue, reason: 'seed ${gm['seed']}: 最後は終局');
      }
      expect(steps, greaterThan(1000));
    });
  });
}
