import 'package:flutter/material.dart';

enum ObstacleType { typeA, typeB, typeC }

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
