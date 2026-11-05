import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:darewire/core/theme.dart';
import 'package:darewire/data/models.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('there are four themes and neon is the default', () {
    expect(palettes.map((p) => p.id), ['neon', 'aurora', 'crimson', 'spectrum']);
    expect(palById(null).id, 'neon');
    expect(palById('nope').id, 'neon');
  });

  test('every theme keeps text readable: body text on the background and white on the main button colour', () {
    for (final p in palettes) {
      expect(_contrast(C.text, p.bg), greaterThan(7), reason: '${p.id} body text');
      expect(_contrast(const Color(0xFFFFFFFF), p.primary), greaterThan(4.4), reason: '${p.id} button text');
    }
  });

  test('there are 12 built-in avatars named a01 to a12', () {
    expect(avatarKeys.length, 12);
    expect(avatarKeys.first, 'a01');
    expect(avatarKeys.last, 'a12');
  });

  test('Duel parses, and knows whose move it is', () {
    Duel make(String role, String status) => Duel.fromJson({
          'id': 'd1', 'role': role, 'status': status, 'title': 'Weather report', 'objective': 'Give a forecast', 'category': 'perform',
          'other': {'id': 'u2', 'handle': 'bobby', 'avatar': 'a05'}, 'difficulty': 2, 'reward': 30, 'rewarded': 0, 'criteria': ['done'],
        });
    expect(make('target', 'pending').myMove, true);
    expect(make('challenger', 'pending').myMove, false);
    expect(make('target', 'accepted').myMove, true);
    expect(make('challenger', 'submitted').myMove, true);
    expect(make('target', 'submitted').myMove, false);
    expect(make('target', 'completed').isOpen, false);
    expect(make('target', 'pending').otherHandle, 'bobby');
    expect(Duel.fromJson(const {}).otherAvatar, 'a01');
  });

  test('QuestsState and WalletState parse and never trust missing fields', () {
    final q = QuestsState.fromJson({
      'streak': 3,
      'week': [
        {'label': 'M', 'active': true, 'today': false, 'future': false},
        {'label': 'T', 'active': false, 'today': true, 'future': false},
      ],
      'quests': [
        {'id': 'play_round', 'title': 'Take the stage', 'desc': 'x', 'goal': 1, 'reward': 10, 'progress': 1, 'claimed': false},
        {'id': 'send_duel', 'title': 'Throw down', 'desc': 'x', 'goal': 1, 'reward': 15, 'progress': 0, 'claimed': false},
      ],
    });
    expect(q.streak, 3);
    expect(q.week.length, 2);
    expect(q.claimable, 1);
    expect(QuestsState.fromJson(const {}).quests, isEmpty);
    final w = WalletState.fromJson({'balance': 120, 'completed': 4, 'activity': [{'id': 'a', 'amount': 25, 'kind': 'quest', 'note': 'x', 'at': 1700000000000}], 'cashOut': {'available': false, 'note': 'n'}});
    expect(w.balance, 120);
    expect(w.cashOutAvailable, false);
    expect(w.activity.single.amount, 25);
    expect(WalletState.fromJson(const {}).cashOutAvailable, false);
  });

  test('SessionSummary shows who is on stage and what dare is being played', () {
    final s = SessionSummary.fromJson({
      'id': 's1', 'code': 'ABC123', 'title': 'Friday', 'phase': 'LIVE_ROUND', 'watchers': 5, 'round': 2,
      'player': {'id': 'u1', 'handle': 'vera', 'avatar': 'a03', 'streak': 2}, 'dare': {'title': 'Sock Court', 'difficulty': 3, 'category': 'perform'},
    });
    expect(s.onStage, true);
    expect(s.inRound, true);
    expect(s.dareTitle, 'Sock Court');
    expect(s.playerStreak, 2);
    final empty = SessionSummary.fromJson({'id': 's2', 'code': 'X', 'title': 'Open', 'phase': 'LOBBY', 'watchers': 0, 'round': 0, 'player': null});
    expect(empty.onStage, false);
  });
}
