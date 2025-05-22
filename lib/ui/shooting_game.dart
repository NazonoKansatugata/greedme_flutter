import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

enum EnemyType { typeA, typeB, typeC }

class Bullet {
  double x;
  double y;
  double dy;
  double dx;
  bool isPlayer;
  int type; // 弾の種類
  Bullet({
    required this.x,
    required this.y,
    this.dy = 0,
    this.dx = 0,
    required this.isPlayer,
    required this.type,
  });
  void move() {
    x += dx;
    y += dy;
  }
}

class Enemy {
  double x;
  double y;
  final EnemyType type;
  double speed;
  int fireInterval; // 何フレームごとに弾を撃つか
  int fireCounter = 0;

  Enemy({required this.x, required this.y, required this.type})
      : speed = _getSpeed(type),
        fireInterval = _getFireInterval(type);

  void move() {
    y += speed;
  }

  static double _getSpeed(EnemyType type) {
    switch (type) {
      case EnemyType.typeA:
        return 2.5;
      case EnemyType.typeB:
        return 1.5;
      case EnemyType.typeC:
        return 3.5;
    }
  }

  static int _getFireInterval(EnemyType type) {
    switch (type) {
      case EnemyType.typeA:
        return 90;
      case EnemyType.typeB:
        return 60;
      case EnemyType.typeC:
        return 120;
    }
  }

  Widget getWidget() {
    switch (type) {
      case EnemyType.typeA:
        return Container(width: 30, height: 30, color: Colors.green, child: const Icon(Icons.bug_report, color: Colors.white));
      case EnemyType.typeB:
        return Container(
          width: 40,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.yellow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.android, color: Colors.black),
        );
      case EnemyType.typeC:
        return Icon(Icons.star, color: Colors.pink, size: 32);
    }
  }

  double getWidth() {
    switch (type) {
      case EnemyType.typeA:
        return 30;
      case EnemyType.typeB:
        return 40;
      case EnemyType.typeC:
        return 32;
    }
  }

  double getHeight() {
    switch (type) {
      case EnemyType.typeA:
        return 30;
      case EnemyType.typeB:
        return 20;
      case EnemyType.typeC:
        return 32;
    }
  }
}

class Player {
  double x;
  double y;
  Player({required this.x, required this.y});

  Bullet shoot(int bulletType) {
    return Bullet(x: x, y: y, dy: -8, isPlayer: true, type: bulletType);
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
  List<Enemy> enemies = [];
  Timer? timer;
  Timer? leftMoveTimer;
  Timer? rightMoveTimer;
  Timer? upMoveTimer;
  Timer? downMoveTimer;
  Timer? shootTimer;
  Random rand = Random();
  double screenWidth = 600;
  double screenHeight = 900;
  bool isGameOver = false;

  Map<EnemyType, int> scores = {
    EnemyType.typeA: 0,
    EnemyType.typeB: 0,
    EnemyType.typeC: 0,
  };

  WebSocketChannel? _channel;

  int bulletType = 0; // 0:1方向速射, 1:3方向遅射
  static const bulletColors = [Colors.red, Colors.blue];

  // 移動速度段階
  final List<int> moveSteps = [30, 45, 60];
  int moveStepIndex = 0; // 0:遅い, 1:普通, 2:速い
  int get moveStep => moveSteps[moveStepIndex];

  @override
  void initState() {
    super.initState();
    player = Player(x: 150, y: 500);
    timer = Timer.periodic(const Duration(milliseconds: 16), _update);

    // WebSocket接続
    _channel = WebSocketChannel.connect(Uri.parse('wss://greendme-websocket.onrender.com'));
    _channel!.sink.add(jsonEncode({'type': 'register', 'role': 'game'}));
    _channel!.stream.listen((message) {
      try {
        final msg = jsonDecode(message);
        if (msg['type'] == 'input') {
          final input = msg['data'];
          if (input == 'left') {
            _movePlayer(-moveStep.toDouble(), 0);
          } else if (input == 'right') {
            _movePlayer(moveStep.toDouble(), 0);
          } else if (input == 'up') {
            _movePlayer(0, -moveStep.toDouble());
          } else if (input == 'down') {
            _movePlayer(0, moveStep.toDouble());
          } else if (input == 'A') {
            _changeBulletType();
          } else if (input == 'B') {
            _changeMoveSpeed();
          }
        }
      } catch (e) {
        print('WebSocket受信エラー: $e');
      }
    }, onError: (error) {
      print('WebSocketエラー: $error');
    });

    _startShooting();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    timer?.cancel();
    leftMoveTimer?.cancel();
    rightMoveTimer?.cancel();
    upMoveTimer?.cancel();
    downMoveTimer?.cancel();
    shootTimer?.cancel();
    super.dispose();
  }

  void _changeMoveSpeed() {
    setState(() {
      moveStepIndex = (moveStepIndex + 1) % moveSteps.length;
    });
  }

  void _movePlayer(double dx, [double dy = 0]) {
    if (isGameOver) return;
    setState(() {
      player.x += dx;
      player.y += dy;
      double maxX = screenWidth - 30;
      double maxY = screenHeight - 30;
      if (player.x < 0) player.x = 0;
      if (player.x > maxX) player.x = maxX;
      if (player.y < 0) player.y = 0;
      if (player.y > maxY) player.y = maxY;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (isGameOver) return;
    setState(() {
      player.x += details.delta.dx;
      player.y += details.delta.dy;
      double maxX = screenWidth - 30;
      double maxY = screenHeight - 30;
      if (player.x < 0) player.x = 0;
      if (player.x > maxX) player.x = maxX;
      if (player.y < 0) player.y = 0;
      if (player.y > maxY) player.y = maxY;
    });
  }

  void _update(Timer timer) {
    if (isGameOver) return;
    setState(() {
      // 弾移動
      bullets.forEach((b) => b.move());
      bullets.removeWhere((b) => b.y < -20 || b.y > screenHeight + 20);

      // 敵移動・攻撃
      for (var enemy in enemies) {
        enemy.move();
        enemy.fireCounter++;
        if (enemy.fireCounter >= enemy.fireInterval) {
          enemy.fireCounter = 0;
          // 敵弾発射
          bullets.add(Bullet(
            x: enemy.x + enemy.getWidth() / 2 - 3,
            y: enemy.y + enemy.getHeight(),
            dy: 6,
            isPlayer: false,
            type: 0,
          ));
        }
      }
      enemies.removeWhere((e) => e.y > screenHeight + 40);

      // 弾と敵の当たり判定
      List<Bullet> removeBullets = [];
      List<Enemy> removeEnemies = [];
      for (var bullet in bullets.where((b) => b.isPlayer)) {
        for (var enemy in enemies) {
          if (_hitTest(bullet, enemy)) {
            removeBullets.add(bullet);
            removeEnemies.add(enemy);
            scores[enemy.type] = (scores[enemy.type] ?? 0) + 1;
            break;
          }
        }
      }
      bullets.removeWhere((b) => removeBullets.contains(b));
      enemies.removeWhere((e) => removeEnemies.contains(e));

      // 敵弾とプレイヤーの当たり判定
      for (var bullet in bullets.where((b) => !b.isPlayer)) {
        if (_playerHitTest(bullet)) {
          _endGame();
          return;
        }
      }
      // 敵本体とプレイヤーの当たり判定
      for (var enemy in enemies) {
        if (_playerHitTestEnemy(enemy)) {
          _endGame();
          return;
        }
      }

      // 一定間隔で敵生成
      if (timer.tick % 60 == 0) {
        enemies.add(_randomEnemy());
      }
    });
  }

  bool _hitTest(Bullet b, Enemy e) {
    double bw = 6, bh = 12;
    double ew = e.getWidth(), eh = e.getHeight();
    return !(b.x + bw < e.x ||
        b.x > e.x + ew ||
        b.y + bh < e.y ||
        b.y > e.y + eh);
  }

  bool _playerHitTest(Bullet b) {
    double bw = 6, bh = 12;
    double px = player.x, py = player.y, pw = 30, ph = 30;
    return !(b.x + bw < px ||
        b.x > px + pw ||
        b.y + bh < py ||
        b.y > py + ph);
  }

  bool _playerHitTestEnemy(Enemy e) {
    double px = player.x, py = player.y, pw = 30, ph = 30;
    double ew = e.getWidth(), eh = e.getHeight();
    return !(e.x + ew < px ||
        e.x > px + pw ||
        e.y + eh < py ||
        e.y > py + ph);
  }

  Enemy _randomEnemy() {
    int type = rand.nextInt(3);
    double maxWidth = screenWidth - 40;
    double x = rand.nextDouble() * maxWidth;
    return Enemy(x: x, y: 0, type: EnemyType.values[type]);
  }

  void _onTapDown(TapDownDetails details) {
    if (isGameOver) return;
    bullets.add(player.shoot(bulletType));
  }

  void _endGame() async {
    isGameOver = true;
    timer?.cancel();

    // スコアを2倍して保存
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .set({
      'score_typeA': (scores[EnemyType.typeA] ?? 0) * 2,
      'score_typeB': (scores[EnemyType.typeB] ?? 0) * 2,
      'score_typeC': (scores[EnemyType.typeC] ?? 0) * 2,
    }, SetOptions(merge: true));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('ゲーム終了'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('TypeA: ${(scores[EnemyType.typeA] ?? 0) * 2}'),
            Text('TypeB: ${(scores[EnemyType.typeB] ?? 0) * 2}'),
            Text('TypeC: ${(scores[EnemyType.typeC] ?? 0) * 2}'),
            const SizedBox(height: 16),
            Text('合計: ${(scores.values.reduce((a, b) => a + b)) * 2}'),
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

  void _changeBulletType() {
    setState(() {
      bulletType = (bulletType + 1) % 2;
    });
    _startShooting();
  }

  bool _isShooting = false;
  void _startShooting() {
    _isShooting = false;
    shootTimer?.cancel();
    _isShooting = true;
    shootTimer = Timer.periodic(
      Duration(milliseconds: bulletType == 0 ? 200 : 1000),
      (_) {
        if (!isGameOver && _isShooting) {
          setState(() {
            if (bulletType == 0) {
              // 1方向速射
              bullets.add(player.shoot(0));
            } else {
              // 3方向遅射
              bullets.add(Bullet(x: player.x, y: player.y, dy: -8, isPlayer: true, type: 1));
              bullets.add(Bullet(x: player.x, y: player.y, dy: -8, isPlayer: true, type: 1)
                ..x -= 10
                ..dy = -8
                ..dx = -3);
              bullets.add(Bullet(x: player.x, y: player.y, dy: -8, isPlayer: true, type: 1)
                ..x += 10
                ..dy = -8
                ..dx = 3);
            }
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    screenWidth = 600;
    screenHeight = 900;
    if (!focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!focusNode.hasFocus) {
          focusNode.requestFocus();
        }
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SizedBox(
          width: screenWidth,
          height: screenHeight,
          child: RawKeyboardListener(
            focusNode: focusNode,
            autofocus: true,
            onKey: (event) {
              if (event is RawKeyDownEvent && !event.repeat) {
                if (event.isKeyPressed(LogicalKeyboardKey.arrowLeft)) {
                  _movePlayer(-moveStep.toDouble(), 0);
                }
                if (event.isKeyPressed(LogicalKeyboardKey.arrowRight)) {
                  _movePlayer(moveStep.toDouble(), 0);
                }
                if (event.isKeyPressed(LogicalKeyboardKey.arrowUp)) {
                  _movePlayer(0, -moveStep.toDouble());
                }
                if (event.isKeyPressed(LogicalKeyboardKey.arrowDown)) {
                  _movePlayer(0, moveStep.toDouble());
                }
                if (event.isKeyPressed(LogicalKeyboardKey.keyA)) {
                  _changeBulletType();
                }
                if (event.isKeyPressed(LogicalKeyboardKey.keyB)) {
                  _changeMoveSpeed();
                }
              }
            },
            child: GestureDetector(
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onTapDown: _onTapDown,
              child: Stack(
                children: [
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
                    child: Container(
                      width: 6,
                      height: 12,
                      color: bulletColors[b.type % bulletColors.length],
                    ),
                  )),
                  // 敵
                  ...enemies.map((e) => Positioned(
                    left: e.x,
                    top: e.y,
                    child: e.getWidget(),
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
                            onTapDown: (_) => _movePlayer(-moveStep.toDouble(), 0),
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
                            onTapDown: (_) => _changeBulletType(),
                            child: ElevatedButton(
                              onPressed: null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: bulletColors[bulletType],
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(18),
                              ),
                              child: const Icon(Icons.change_circle, size: 28),
                            ),
                          ),
                          const SizedBox(width: 20),
                          GestureDetector(
                            onTapDown: (_) => _movePlayer(moveStep.toDouble(), 0),
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
                          const SizedBox(width: 20),
                          GestureDetector(
                            onTapDown: (_) => _movePlayer(0, -moveStep.toDouble()),
                            child: ElevatedButton(
                              onPressed: null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueGrey,
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(18),
                              ),
                              child: const Icon(Icons.arrow_upward, size: 32),
                            ),
                          ),
                          const SizedBox(width: 20),
                          GestureDetector(
                            onTapDown: (_) => _movePlayer(0, moveStep.toDouble()),
                            child: ElevatedButton(
                              onPressed: null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueGrey,
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(18),
                              ),
                              child: const Icon(Icons.arrow_downward, size: 32),
                            ),
                          ),
                          const SizedBox(width: 20),
                          GestureDetector(
                            onTapDown: (_) => _changeMoveSpeed(),
                            child: ElevatedButton(
                              onPressed: null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(18),
                              ),
                              child: Icon(Icons.speed, size: 28, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isGameOver)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.7),
                        child: Center(
                          child: AlertDialog(
                            title: const Text('ゲーム終了'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('TypeA: ${(scores[EnemyType.typeA] ?? 0) * 2}'),
                                Text('TypeB: ${(scores[EnemyType.typeB] ?? 0) * 2}'),
                                Text('TypeC: ${(scores[EnemyType.typeC] ?? 0) * 2}'),
                                const SizedBox(height: 16),
                                Text('合計: ${(scores.values.reduce((a, b) => a + b)) * 2}'),
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
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
