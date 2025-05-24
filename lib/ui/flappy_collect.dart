import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

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
  bool isGameOver = false;
  double screenWidth = 300;
  double screenHeight = 600;
  Random rand = Random();

  Map<CollectType, int> scores = {
    CollectType.typeA: 0,
    CollectType.typeB: 0,
    CollectType.typeC: 0,
  };

  WebSocketChannel? _channel;

  @override
  void initState() {
    super.initState();
    gameTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _update());
    objectTimer = Timer.periodic(const Duration(milliseconds: 900), (_) => _spawnObject()); // 頻度を下げる

    // WebSocket連動
    _channel = WebSocketChannel.connect(Uri.parse('wss://greendme-websocket.onrender.com'));
    _channel!.sink.add(jsonEncode({'type': 'register', 'role': 'game', 'userId': widget.userId}));
    _channel!.stream.listen((message) {
      try {
        final msg = jsonDecode(message);
        if (msg['type'] == 'input') {
          final input = msg['data'];
          // ジャンプ操作に割り当て
          if (input == 'up' || input == 'A' || input == 'B' || input == 'left' || input == 'right' || input == 'down') {
            _jump();
          }
        }
      } catch (e) {
        print('WebSocket受信エラー: $e');
      }
    }, onError: (error) {
      print('WebSocketエラー: $error');
    });
  }

  @override
  void dispose() {
    _channel?.sink.close();
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

      // 取り逃し判定
      for (var obj in objects) {
        if (!obj.collected && obj.x < 20) {
          // 画面左端を超えた未取得オブジェクトがあれば即終了
          _endGame();
          return;
        }
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
      'score_typeA': scores[CollectType.typeA],
      'score_typeB': scores[CollectType.typeB],
      'score_typeC': scores[CollectType.typeC],
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
            onPressed: () async {
              Navigator.of(context).pop();
              // リダイレクト
              final url = Uri.parse('https://unity-greendme.web.app/');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
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
            // タイマー表示は削除
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
