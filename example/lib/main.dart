import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ez_mqtt_client/ez_mqtt_client.dart';

const TAG = "MQTT";

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MQTT Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MqttTest(title: 'MQTT Test'),
    );
  }
}

class MqttTest extends StatefulWidget {
  MqttTest({Key key, this.title}) : super(key: key);
  final String title;

  @override
  _MqttTestState createState() => _MqttTestState();
}

class _MqttTestState extends State<MqttTest> {
  EzMqttClient mqttClient;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    mqttClient = EzMqttClient.nonSecure(
        url: '127.0.0.1', clientId: Utils.uuid, enableLogs: true);

    print('[$TAG] is client connected: ${mqttClient.isConnected}');
    await mqttClient
        .connect()
        .then((connected) => print("[$TAG] mqtt client connected: $connected"))
        .catchError(
            (error) => print('[$TAG] unable to connect, error: $error'));
    print('[$TAG] is client connected: ${mqttClient.isConnected}');

    final topic = "home/topic/listen";
    subscribe(topic);
  }

  Future<void> sendMessages(
      {String message, String topic, int count, Duration interval}) async {
    countUpTimer(count, interval).listen((tick) {
      final messageFull =
          '[$tick][${DateTime.now().toIso8601String()}] $message';
      print('[$TAG] sending msg: {$messageFull}');
      mqttClient
          .publishMessage(
              topic: topic, message: messageFull, qosLevel: MqttQos.exactlyOnce)
          .then((message) => print('[$TAG] msg sent: $message'))
          .catchError((error) {
        print(
            'Received error on publishMessage\n**topic: $topic\n**message: $message\n**error: $error');
      });
    });
  }

  Future<void> subscribe(String topic) async {
    await mqttClient
        .subscribeToTopic(
            topic: topic,
            onMessage: (topic, message) =>
                print('[$TAG] received message on topic $topic:\n $message'))
        .then((value) => print('[$TAG] subscribed to topic: $value'))
        .catchError((error) => print(
            '[$TAG] failed to subscribe to topic: $topic. \n\nerror: \n$error'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text("Running MQTT"),
              RaisedButton(
                child: Text("Send 5 Messages"),
                onPressed: () => sendMessages(
                    topic: "home/topic/send",
                    message: "Test message",
                    interval: Duration(seconds: 1),
                    count: 5),
              ),
              RaisedButton(
                child: Text("Send 50 Messages"),
                onPressed: () => sendMessages(
                    topic: "home/topic/send",
                    message: "Test Message",
                    interval: Duration(milliseconds: 1000),
                    count: 50),
              ),
              RaisedButton(
                child: Text("Disconnect"),
                onPressed: () => mqttClient.resetConnection(),
              ),
              RaisedButton(
                child: Text("Subscribe"),
                onPressed: () => subscribe("home/topic/listen"),
              )
            ],
          ),
        ));
  }

  Stream<int> countUpTimer(int count, Duration interval) async* {
    for (int i = 0; i < count; i++) {
      await Future.delayed(interval);
      yield i;
    }
  }
}
