import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum MoleType { typeA, typeB, typeC }

class Mole {
  final int holeIndex;
  final MoleType type;
  bool visible;
  Mole({required this.holeIndex, required this.type, this.visible = true});
}

class WhackAMolePage extends StatefulWidget {
  final String userId;
  const WhackAMolePage({Key? key, required this.userId}) : super(key: key);

  @override
  State<WhackAMolePage> createState() => _WhackAMolePageState();
}

class _WhackAMolePageState extends State<WhackAMolePage> {
  static const int holeCount = 49; // 7x7
  static const int rowCount = 7;
  static const int colCount = 7;
  final Random rand = Random();
  List<Mole?> holes = List.filled(holeCount, null);
  Timer? moleTimer;
  Timer? gameTimer;
  int timeLeft = 30;
  bool isGameOver = false;

  Map<MoleType, int> scores = {
    MoleType.typeA: 0,
    MoleType.typeB: 0,
    MoleType.typeC: 0,
  };

  // もぐらごとに次の出現までのカウント
  List<int?> moleTimers = List.filled(3, null); // [A,B,C]の残りtick
  List<int?> molePositions = List.filled(3, null); // [A,B,C]の穴index

  @override
  void initState() {
    super.initState();
    // それぞれのもぐらの初回出現タイミングをランダムに
    for (int i = 0; i < 3; i++) {
      moleTimers[i] = rand.nextInt(5) + 5; // 5~9tick後（頻度UP）
      molePositions[i] = null;
    }
    moleTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tickMoles()); // 頻度UP
    gameTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted && !isGameOver) {
        setState(() {
          timeLeft--;
          if (timeLeft <= 0) {
            _endGame();
          }
        });
      }
    });
  }

  void _tickMoles() {
    if (isGameOver) return;
    setState(() {
      holes = List.filled(holeCount, null);
      for (int i = 0; i < 3; i++) {
        if (moleTimers[i] != null) {
          moleTimers[i] = moleTimers[i]! - 1;
          if (moleTimers[i]! <= 0) {
            int idx;
            do {
              idx = rand.nextInt(holeCount);
            } while (holes[idx] != null);
            holes[idx] = Mole(holeIndex: idx, type: MoleType.values[i]);
            molePositions[i] = idx;
            moleTimers[i] = rand.nextInt(7) + 7; // 7~13tick後（頻度UP）
          } else if (molePositions[i] != null) {
            holes[molePositions[i]!] = Mole(holeIndex: molePositions[i]!, type: MoleType.values[i]);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    moleTimer?.cancel();
    gameTimer?.cancel();
    super.dispose();
  }

  void _hitMole(int idx) {
    if (isGameOver) return;
    setState(() {
      final mole = holes[idx];
      if (mole != null && mole.visible) {
        scores[mole.type] = (scores[mole.type] ?? 0) + 1;
        // 叩かれたらそのもぐらは消す
        for (int i = 0; i < 3; i++) {
          if (molePositions[i] == idx) {
            molePositions[i] = null;
            // 次の出現までのカウントをセット
            moleTimers[i] = rand.nextInt(15) + 15;
          }
        }
        holes[idx] = null;
      }
    });
  }

  void _endGame() async {
    isGameOver = true;
    moleTimer?.cancel();
    gameTimer?.cancel();

    // Firestoreにスコア保存
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .set({
      'wam_score_typeA': scores[MoleType.typeA],
      'wam_score_typeB': scores[MoleType.typeB],
      'wam_score_typeC': scores[MoleType.typeC],
      'wam_updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('もぐらたたき終了'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('TypeA: ${scores[MoleType.typeA]}'),
            Text('TypeB: ${scores[MoleType.typeB]}'),
            Text('TypeC: ${scores[MoleType.typeC]}'),
            const SizedBox(height: 16),
            Text('合計: ${scores.values.reduce((a, b) => a + b)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _moleWidget(MoleType type) {
    switch (type) {
      case MoleType.typeA:
        return Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: const Center(child: Text('A', style: TextStyle(fontSize: 28, color: Colors.white))),
        );
      case MoleType.typeB:
        return Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.yellow,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: const Center(child: Text('B', style: TextStyle(fontSize: 28, color: Colors.black))),
        );
      case MoleType.typeC:
        return Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.pink,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: const Center(child: Text('C', style: TextStyle(fontSize: 28, color: Colors.white))),
        );
    }
  }

  Widget _holeWidget(int idx) {
    final mole = holes[idx];
    return GestureDetector(
      onTap: () => _hitMole(idx),
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.brown[300],
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.brown[700]!,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: mole != null && mole.visible
            ? _moleWidget(mole.type)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.brown[200],
      body: Stack(
        children: [
          // タイマー表示
          Positioned(
            top: 20,
            left: 20,
            child: Text(
              '残り: $timeLeft 秒',
              style: const TextStyle(color: Colors.black, fontSize: 20),
            ),
          ),
          // 穴とモグラ
          Center(
            child: SizedBox(
              width: 7 * 48,
              height: 7 * 48,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                ),
                itemCount: holeCount,
                itemBuilder: (context, idx) => _holeWidget(idx),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
