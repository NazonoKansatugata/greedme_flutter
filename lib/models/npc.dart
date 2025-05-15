import 'bullet.dart';

class NPC {
  double x;
  double y;
  NPC({required this.x, required this.y});

  Bullet shoot() {
    return Bullet(x: x, y: y + 30, dy: 6, isPlayer: false);
  }
}
