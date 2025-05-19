import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum CollectType { typeA, typeB, typeC }

class CollectObject {
  double x;
  double y;
  final CollectType type;
  bool collected = false;
  CollectObject({required this.x, required this.y, required this.type});
}

class FlappyCollectPage extends StatefulWidget {
  final String userId;
  const FlappyCollectPage({Key? key, required this.userId}) : super(key: key);

  @override
  State<FlappyCollectPage> createState() => _FlappyCollectPageState();
}

class _FlappyCollectPageState extends State<FlappyCollectPage> {
  double playerY = 0.5;
  double velocity = 0;
  double gravity = 0.0012;
  double jumpPower = -0.025;
  Timer? gameTimer;
  Timer? objectTimer;
  List<CollectObject> objects = [];
  int timeLeft = 30;
  bool isGameOver = false;
  double screenWidth = 300;
  double screenHeight = 600;
  Random rand = Random();

  Map<CollectType, int> scores = {
    CollectType.typeA: 0,
    CollectType.typeB: 0,
    CollectType.typeC: 0,
  };

  @override
  void initState() {
    super.initState();
    gameTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _update());
    objectTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) => _spawnObject());
    Timer.periodic(const Duration(seconds: 1), (t) {
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
    gameTimer?.cancel();
    objectTimer?.cancel();
    super.dispose();
  }

  void _update() {
    if (isGameOver) return;
    setState(() {
      // 物理
      velocity += gravity;
      playerY += velocity;
      if (playerY < 0) {
        playerY = 0;
        velocity = 0;
      }
      if (playerY > 1) {
        playerY = 1;
        velocity = 0;
      }


      for (var obj in objects) {
        obj.x -= 4;
      }

      objects.removeWhere((o) => o.x < -40 || o.collected);

 
      for (var obj in objects) {
        if (!obj.collected && _hitTest(obj)) {
          obj.collected = true;
          scores[obj.type] = (scores[obj.type] ?? 0) + 1;
        }
      }
    });
  }

  bool _hitTest(CollectObject obj) {

    double px = 60, py = playerY * (screenHeight - 60) + 30;
    double pw = 40, ph = 40;
    double ox = obj.x, oy = obj.y;
    double ow = 36, oh = 36;
    return !(px + pw < ox || px > ox + ow || py + ph < oy || py > oy + oh);
  }

  void _spawnObject() {
    if (isGameOver) return;
    setState(() {
      final type = CollectType.values[rand.nextInt(3)];
      final y = rand.nextDouble() * (screenHeight - 80) + 20;
      objects.add(CollectObject(
        x: screenWidth + 40,
        y: y,
        type: type,
      ));
    });
  }

  void _jump() {
    if (isGameOver) return;
    setState(() {
      velocity = jumpPower;
    });
  }

  void _endGame() async {
    isGameOver = true;
    gameTimer?.cancel();
    objectTimer?.cancel();

    // Firestoreにスコア保存
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .set({
      'core_typeA': scores[CollectType.typeA],
      'score_typeB': scores[CollectType.typeB],
      'score_typeC': scores[CollectType.typeC],
      'flappy_updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('フラッピーバード風ゲーム終了'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('TypeA: ${scores[CollectType.typeA]}'),
            Text('TypeB: ${scores[CollectType.typeB]}'),
            Text('TypeC: ${scores[CollectType.typeC]}'),
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

  Widget _objectWidget(CollectType type) {
    switch (type) {
      case CollectType.typeA:
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
          child: const Center(child: Text('A', style: TextStyle(fontSize: 20, color: Colors.white))),
        );
      case CollectType.typeB:
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.yellow,
            shape: BoxShape.circle,
          ),
          child: const Center(child: Text('B', style: TextStyle(fontSize: 20, color: Colors.black))),
        );
      case CollectType.typeC:
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.pink,
            shape: BoxShape.circle,
          ),
          child: const Center(child: Text('C', style: TextStyle(fontSize: 20, color: Colors.white))),
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

    double playerTop = playerY * (screenHeight - 60);

    return Scaffold(
      backgroundColor: Colors.lightBlue[100],
      body: GestureDetector(
        onTap: _jump,
        child: Stack(
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
            // プレイヤー
            Positioned(
              left: 60,
              top: playerTop + 30,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.brown, width: 3),
                ),
                child: const Icon(Icons.arrow_upward, color: Colors.white),
              ),
            ),
            // オブジェクト
            ...objects.map((o) => Positioned(
              left: o.x,
              top: o.y,
              child: _objectWidget(o.type),
            )),
            // ジャンプボタン（スマホ用）
            if (!isGameOver)
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Center(
                  child: ElevatedButton(
                    onPressed: _jump,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(24),
                    ),
                    child: const Icon(Icons.arrow_upward, size: 32, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
