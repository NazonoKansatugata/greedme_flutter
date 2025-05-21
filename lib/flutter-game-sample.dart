import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() => runApp(GameScreen());

class GameScreen extends StatefulWidget {
  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late WebSocketChannel channel;
  String lastInput = '';
  double playerX = 150;
  double playerY = 500;
  List<Offset> bullets = [];

  @override
  void initState() {
    super.initState();
    channel = WebSocketChannel.connect(Uri.parse('ws://localhost:8080'));
    channel.sink.add(jsonEncode({'type': 'register', 'role': 'game'}));
    channel.stream.listen((message) {
      final msg = jsonDecode(message);
      if (msg['type'] == 'input') {
        setState(() {
          lastInput = msg['data'].toString();
        });
        // コントローラーからの指示でプレイヤーを動かす
        if (msg['data'] == 'left') {
          setState(() {
            playerX -= 20;
            if (playerX < 0) playerX = 0;
          });
        } else if (msg['data'] == 'right') {
          setState(() {
            playerX += 20;
            if (playerX > 300) playerX = 300;
          });
        } else if (msg['data'] == 'shoot') {
          setState(() {
            bullets.add(Offset(playerX + 15, playerY));
          });
        }
      }
    });

    // 弾の移動タイマー
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 16));
      if (bullets.isNotEmpty) {
        setState(() {
          bullets = bullets
              .map((b) => Offset(b.dx, b.dy - 8))
              .where((b) => b.dy > 0)
              .toList();
        });
      }
      return true;
    });
  }

  @override
  void dispose() {
    channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('ゲーム画面')),
        body: Center(
          child: SizedBox(
            width: 360,
            height: 600,
            child: Stack(
              children: [
                // プレイヤー
                Positioned(
                  left: playerX,
                  top: playerY,
                  child: Container(
                    width: 30,
                    height: 30,
                    color: Colors.blue,
                  ),
                ),
                // 弾
                ...bullets.map((b) => Positioned(
                  left: b.dx + 6,
                  top: b.dy,
                  child: Container(width: 6, height: 12, color: Colors.red),
                )),
                // 最後の入力表示
                Positioned(
                  top: 20,
                  left: 20,
                  child: Text('最後の入力: $lastInput', style: TextStyle(fontSize: 20, color: Colors.black)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
