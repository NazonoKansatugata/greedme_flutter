import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum MoleType { typeA, typeB, typeC }

class Mole {
  final double x;
  final double y;
  final MoleType type;
  Mole({required this.x, required this.y, required this.type});
}

class WhackAMolePage extends StatefulWidget {
  final String userId;
  const WhackAMolePage({Key? key, required this.userId}) : super(key: key);

  @override
  State<WhackAMolePage> createState() => _WhackAMolePageState();
}

class _WhackAMolePageState extends State<WhackAMolePage> {
  final Random rand = Random();
  List<Mole> moles = [];
  Timer? moleTimer;
  Timer? gameTimer;
  int timeLeft = 30;
  bool isGameOver = false;
  double screenWidth = 300;
  double screenHeight = 600;

  Map<MoleType, int> scores = {
    MoleType.typeA: 0,
    MoleType.typeB: 0,
    MoleType.typeC: 0,
  };

  @override
  void initState() {
    super.initState();
    _spawnMoles();
    moleTimer = Timer.periodic(const Duration(milliseconds: 900), (_) => _spawnMoles());
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

  @override
  void dispose() {
    moleTimer?.cancel();
    gameTimer?.cancel();
    super.dispose();
  }

  void _spawnMoles() {
    if (isGameOver) return;
    setState(() {
      moles.clear();
      for (int i = 0; i < 3; i++) {
        final type = MoleType.values[i];
        final x = rand.nextDouble() * (screenWidth - 80) + 20;
        final y = rand.nextDouble() * (screenHeight - 300) + 100;
        moles.add(Mole(x: x, y: y, type: type));
      }
    });
  }

  void _hitMole(int idx) {
    if (isGameOver) return;
    setState(() {
      final type = moles[idx].type;
      scores[type] = (scores[type] ?? 0) + 1;
      moles.removeAt(idx);
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
      'score_typeA': scores[MoleType.typeA],
      'score_typeB': scores[MoleType.typeB],
      'score_typeC': scores[MoleType.typeC],
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
          ),
          child: const Center(child: Text('C', style: TextStyle(fontSize: 28, color: Colors.white))),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = MediaQuery.of(context).size;
      screenWidth = size.width;
      screenHeight = size.height;
    });

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
          // もぐら
          ...List.generate(moles.length, (i) {
            final mole = moles[i];
            return Positioned(
              left: mole.x,
              top: mole.y,
              child: GestureDetector(
                onTap: () => _hitMole(i),
                child: _moleWidget(mole.type),
              ),
            );
          }),
        ],
      ),
    );
  }
}
