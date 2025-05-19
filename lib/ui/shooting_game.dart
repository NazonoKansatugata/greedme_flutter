import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum ObstacleType { typeA, typeB, typeC }

class Bullet {
  double x;
  double y;
  double dy;
  bool isPlayer;
  Bullet({required this.x, required this.y, required this.dy, required this.isPlayer});
  void move() {
    y += dy;
  }
}

class Obstacle {
  double x;
  double y;
  final ObstacleType type;
  double speed;

  Obstacle({required this.x, required this.y, required this.type})
      : speed = _getSpeed(type);

  void move() {
    y += speed;
  }

  static double _getSpeed(ObstacleType type) {
    switch (type) {
      case ObstacleType.typeA:
        return 3;
      case ObstacleType.typeB:
        return 5;
      case ObstacleType.typeC:
        return 2;
    }
  }

  Widget getWidget() {
    switch (type) {
      case ObstacleType.typeA:
        return Container(width: 30, height: 30, color: Colors.green);
      case ObstacleType.typeB:
        return Container(
          width: 40,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.yellow,
            borderRadius: BorderRadius.circular(10),
          ),
        );
      case ObstacleType.typeC:
        return Icon(Icons.star, color: Colors.pink, size: 32);
    }
  }

  double getWidth() {
    switch (type) {
      case ObstacleType.typeA:
        return 30;
      case ObstacleType.typeB:
        return 40;
      case ObstacleType.typeC:
        return 32;
    }
  }

  double getHeight() {
    switch (type) {
      case ObstacleType.typeA:
        return 30;
      case ObstacleType.typeB:
        return 20;
      case ObstacleType.typeC:
        return 32;
    }
  }
}

class Player {
  double x;
  double y;
  Player({required this.x, required this.y});

  Bullet shoot() {
    return Bullet(x: x, y: y, dy: -8, isPlayer: true);
  }
}

class ShootingGamePage extends StatefulWidget {
  final String userId;
  const ShootingGamePage({Key? key, required this.userId}) : super(key: key);

  @override
  State<ShootingGamePage> createState() => _ShootingGamePageState();
}

class _ShootingGamePageState extends State<ShootingGamePage> {
  late Player player;
  List<Bullet> bullets = [];
  List<Obstacle> obstacles = [];
  Timer? timer;
  Timer? gameTimer;
  Timer? leftMoveTimer;
  Timer? rightMoveTimer;
  Timer? shootTimer;
  Random rand = Random();
  double screenWidth = 300;
  double screenHeight = 600;
  int timeLeft = 30;
  bool isGameOver = false;

  Map<ObstacleType, int> scores = {
    ObstacleType.typeA: 0,
    ObstacleType.typeB: 0,
    ObstacleType.typeC: 0,
  };

  @override
  void initState() {
    super.initState();
    player = Player(x: 150, y: 500);
    timer = Timer.periodic(const Duration(milliseconds: 16), _update);
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
    timer?.cancel();
    gameTimer?.cancel();
    leftMoveTimer?.cancel();
    rightMoveTimer?.cancel();
    shootTimer?.cancel();
    super.dispose();
  }

  void _update(Timer timer) {
    if (isGameOver) return;
    setState(() {
      bullets.forEach((b) => b.move());
      bullets.removeWhere((b) => b.y < 0 || b.y > screenHeight);

      obstacles.forEach((o) => o.move());
      obstacles.removeWhere((o) => o.y > screenHeight);

      List<Bullet> removeBullets = [];
      List<Obstacle> removeObstacles = [];
      for (var bullet in bullets) {
        for (var obs in obstacles) {
          if (_hitTest(bullet, obs)) {
            removeBullets.add(bullet);
            removeObstacles.add(obs);
            scores[obs.type] = (scores[obs.type] ?? 0) + 1;
            break;
          }
        }
      }
      bullets.removeWhere((b) => removeBullets.contains(b));
      obstacles.removeWhere((o) => removeObstacles.contains(o));

      if (timer.tick % 60 == 0) {
        obstacles.add(_randomObstacle());
      }
    });
  }

  bool _hitTest(Bullet b, Obstacle o) {
    double bw = 6, bh = 12;
    double ow = o.getWidth(), oh = o.getHeight();
    return !(b.x + bw < o.x ||
        b.x > o.x + ow ||
        b.y + bh < o.y ||
        b.y > o.y + oh);
  }

  Obstacle _randomObstacle() {
    int type = rand.nextInt(3);
    double x = rand.nextDouble() * (screenWidth - 40);
    switch (type) {
      case 0:
        return Obstacle(x: x, y: 0, type: ObstacleType.typeA);
      case 1:
        return Obstacle(x: x, y: 0, type: ObstacleType.typeB);
      default:
        return Obstacle(x: x, y: 0, type: ObstacleType.typeC);
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (isGameOver) return;
    setState(() {
      player.x += details.delta.dx;
      player.x = player.x.clamp(0, screenWidth - 30);
    });
  }

  void _onTapDown(TapDownDetails details) {
    if (isGameOver) return;
    bullets.add(player.shoot());
  }

  void _movePlayer(double dx) {
    if (isGameOver) return;
    setState(() {
      player.x += dx;
      player.x = player.x.clamp(0, screenWidth - 30);
    });
  }

  void _endGame() async {
    isGameOver = true;
    timer?.cancel();
    gameTimer?.cancel();

    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .set({
      'score_typeA': scores[ObstacleType.typeA],
      'score_typeB': scores[ObstacleType.typeB],
      'score_typeC': scores[ObstacleType.typeC],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('ゲーム終了'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('TypeA: ${scores[ObstacleType.typeA]}'),
            Text('TypeB: ${scores[ObstacleType.typeB]}'),
            Text('TypeC: ${scores[ObstacleType.typeC]}'),
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

  FocusNode focusNode = FocusNode();

  void _startMoveLeft() {
    leftMoveTimer?.cancel();
    leftMoveTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      _movePlayer(-5);
    });
  }

  void _stopMoveLeft() {
    leftMoveTimer?.cancel();
  }

  void _startMoveRight() {
    rightMoveTimer?.cancel();
    rightMoveTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      _movePlayer(5);
    });
  }

  void _stopMoveRight() {
    rightMoveTimer?.cancel();
  }

  // --- 連射制御の整理 ---
  bool _isShooting = false;

  void _startShooting() {
    if (_isShooting) return;
    _isShooting = true;
    shootTimer?.cancel();
    shootTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!isGameOver && _isShooting) {
        setState(() {
          bullets.add(player.shoot());
        });
      }
    });
  }

  void _stopShooting() {
    _isShooting = false;
    shootTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = MediaQuery.of(context).size;
      screenWidth = size.width;
      screenHeight = size.height;
      if (!focusNode.hasFocus) {
        focusNode.requestFocus();
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: RawKeyboardListener(
        focusNode: focusNode,
        autofocus: true,
        onKey: (event) {
          // キー押下時
          if (event is RawKeyDownEvent && !event.repeat) {
            if (event.isKeyPressed(LogicalKeyboardKey.arrowLeft)) {
              _startMoveLeft();
            }
            if (event.isKeyPressed(LogicalKeyboardKey.arrowRight)) {
              _startMoveRight();
            }
            if (event.isKeyPressed(LogicalKeyboardKey.space)) {
              _startShooting();
            }
          }
          // キー離し時
          if (event is RawKeyUpEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _stopMoveLeft();
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _stopMoveRight();
            }
            if (event.logicalKey == LogicalKeyboardKey.space) {
              _stopShooting();
            }
          }
        },
        child: GestureDetector(
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onTapDown: _onTapDown,
          child: Stack(
            children: [
              // タイマー表示
              Positioned(
                top: 20,
                left: 20,
                child: Text(
                  '残り: $timeLeft 秒',
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
              // プレイヤー
              Positioned(
                left: player.x,
                top: player.y,
                child: Container(width: 30, height: 30, color: Colors.blue),
              ),
              // 弾
              ...bullets.map((b) => Positioned(
                left: b.x + 12,
                top: b.y,
                child: Container(width: 6, height: 12, color: Colors.white),
              )),
              // 障害物
              ...obstacles.map((o) => Positioned(
                left: o.x,
                top: o.y,
                child: o.getWidget(),
              )),
              // 操作ボタン
              if (!isGameOver)
                Positioned(
                  bottom: 30,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTapDown: (_) => _startMoveLeft(),
                        onTapUp: (_) => _stopMoveLeft(),
                        onTapCancel: _stopMoveLeft,
                        child: ElevatedButton(
                          onPressed: null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(18),
                          ),
                          child: const Icon(Icons.arrow_left, size: 32),
                        ),
                      ),
                      const SizedBox(width: 20),
                      GestureDetector(
                        onTapDown: (_) => _startShooting(),
                        onTapUp: (_) => _stopShooting(),
                        onTapCancel: _stopShooting,
                        child: ElevatedButton(
                          onPressed: null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(18),
                          ),
                          child: const Icon(Icons.circle, size: 28),
                        ),
                      ),
                      const SizedBox(width: 20),
                      GestureDetector(
                        onTapDown: (_) => _startMoveRight(),
                        onTapUp: (_) => _stopMoveRight(),
                        onTapCancel: _stopMoveRight,
                        child: ElevatedButton(
                          onPressed: null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(18),
                          ),
                          child: const Icon(Icons.arrow_right, size: 32),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
