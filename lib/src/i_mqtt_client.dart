library mqttclient;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';

typedef MessageReceivedCallback = void Function(String, String);

abstract class IMqttClient {
  String get url;
  int get port;
  String get clientId;
  bool get secure;
  bool get enableLogs;
  File get secureCertificate;
  Duration get timeOut;
  bool get isConnected;

  Future<bool> connect({String username, String password});
  Future<void> disconnect();

  Future<bool> subscribeToTopic({
    @required String topic,
    @required MessageReceivedCallback onMessage,
    MqttQos qosLevel = MqttQos.exactlyOnce,
  });

  Future<void> unsubscribeFromTopic(String topic);

  Future<Message> publishMessage({
    @required String topic,
    @required String message,
    MqttQos qosLevel = MqttQos.exactlyOnce,
  });
}

class Message {
  final String topic;
  final String message;

  Message(this.topic, this.message);

  @override
  String toString() {
    return 'Message{topic: $topic, message: $message}';
  }
}
