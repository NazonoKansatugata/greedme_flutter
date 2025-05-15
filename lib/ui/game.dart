import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/player.dart';
import '../models/bullet.dart';
import '../models/obstacle.dart';

class GamePage extends StatefulWidget {
  const GamePage({Key? key}) : super(key: key);

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late Player player;
  List<Bullet> bullets = [];
  List<Obstacle> obstacles = [];
  Timer? timer;
  Timer? gameTimer;
  Random rand = Random();
  double screenWidth = 300;
  double screenHeight = 600;
  int timeLeft = 30;
  bool isGameOver = false;

  // スコア
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
    super.dispose();
  }

  void _update(Timer timer) {
    if (isGameOver) return;
    setState(() {
      // 弾の移動
      bullets.forEach((b) => b.move());
      bullets.removeWhere((b) => b.y < 0 || b.y > screenHeight);

      // 障害物の移動
      obstacles.forEach((o) => o.move());
      obstacles.removeWhere((o) => o.y > screenHeight);

      // 弾と障害物の当たり判定
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

      // 一定間隔で障害物を追加
      if (timer.tick % 30 == 0) {
        obstacles.add(_randomObstacle());
      }
    });
  }

  bool _hitTest(Bullet b, Obstacle o) {
    // 矩形の簡易当たり判定
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

  void _endGame() {
    isGameOver = true;
    timer?.cancel();
    gameTimer?.cancel();
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

  // キーボード対応
  FocusNode focusNode = FocusNode();

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
          if (event.isKeyPressed(LogicalKeyboardKey.arrowLeft)) {
            _movePlayer(-15);
          } else if (event.isKeyPressed(LogicalKeyboardKey.arrowRight)) {
            _movePlayer(15);
          } else if (event.isKeyPressed(LogicalKeyboardKey.space)) {
            _onTapDown(TapDownDetails(
              globalPosition: Offset(player.x, player.y),
            ));
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
                      ElevatedButton(
                        onPressed: () => _movePlayer(-20),
                        child: const Icon(Icons.arrow_left),
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton(
                        onPressed: () => bullets.add(player.shoot()),
                        child: const Icon(Icons.circle),
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton(
                        onPressed: () => _movePlayer(20),
                        child: const Icon(Icons.arrow_right),
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
