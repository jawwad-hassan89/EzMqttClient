import 'dart:async';
import 'dart:io';

import 'package:ez_mqtt_client/src/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'i_mqtt_client.dart';
import 'utils.dart';

class EzMqttClient implements IMqttClient {
  static const TAG = "MQTT-Client";
  //************************ Public fields *************************************

  /// The server [url] to connect to
  final String url;

  /// MQTT [port] of the server.
  /// [DEFAULT_NON_SECURE_PORT] is 1883
  /// [DEFAULT_SECURE_PORT] is 8883
  final int port;

  /// This is unique non-null identifier for client.
  /// For a secure connection, a valid non-empty clientId is required
  /// For a non-secure connection, it can be left empty, in which the connection
  /// will be stateless
  ///
  /// For a randomly generated UUID you can use the [Utils.uuid]
  ///
  /// For Mobile devices it is recommended to use the unique device identifier
  /// as the clientId as it allows to get any missing topic subscriptions between
  /// sessions. You can use [Utils.deviceUniqueId] to get a platform specific
  /// unique device identifier
  final String clientId;

  /// Set whether the connection is [secure].
  /// For a secure connection, also provide a valid [secureCertificate] file.
  final bool secure;

  /// The certificate file in case of a [secure] connection.
  /// For a secure connection, a secureCertificate file is also required.
  ///
  /// On a mobile device, the certificate file can be stored in the /assets folder,
  /// and accessed using the Helper method [Utils.getFileFromAssets]
  /// For details on how to use the assets folder, visit https://flutter.dev/docs/development/ui/assets-and-images
  final File secureCertificate;

  /// The maximum [Duration] for the futures to wait before throwing a [TimeoutException]
  final Duration timeOut;

  /// Enable logs for client
  final bool enableLogs;

  /// Check if the client is connected
  bool get isConnected =>
      _client.connectionStatus.state == MqttConnectionState.connected;

  //************************ Private fields ************************************

  /// Map containing the [Completer]s of publish messages requests.
  /// The keys are in the format 'topic##message' as defined in [_generateMapKey]
  final Map<String, Completer<Message>> _publishedMessageRequests = {};

  /// Map containing the [Completer]s of the topic subscription requests.
  /// Key is the topic name
  final Map<String, Completer<bool>> _topicSubscriptionRequests = {};

  /// Map containing the callbacks for the subscribed topics.
  /// Key is the topic name
  final Map<String, MessageReceivedCallback> _topicSubscriptions = {};

  /// [MqttServerClient] instance
  final MqttServerClient _client;

  StreamSubscription _updatesStreamSubscription;
  StreamSubscription _publishedStreamSubscription;
  Completer _onConnectedCompleter;

  String _cachedUserName;
  String _cachedPassword;
  bool _didTimeOut = false;

  factory EzMqttClient.nonSecure({
    @required String url,

    /// for a non-secure connection, the default non-secure port is 1883
    int port = DEFAULT_NON_SECURE_PORT,

    /// For a secure connection, a valid cliendId is required
    /// Use [Utils.uuid] for a randomly generated clientId
    /// or use [Utils.deviceUniqueId] to get the platform specific unique device
    /// identifier for mobile devices
    String clientId = '',
    bool enableLogs = false,
    Duration timeOut = DEFAULT_TIMEOUT,
  }) =>
      EzMqttClient._(
          url: url,
          port: port,
          clientId: clientId,
          secure: false,
          enableLogs: enableLogs,
          timeOut: timeOut);

  factory EzMqttClient.secure({
    @required String url,

    /// For a secure connection, the default port is 8883
    int port = DEFAULT_SECURE_PORT,

    /// For a secure connection, a valid cliendId is required
    /// Use [Utils.uuid] for a randomly generated clientId
    /// or use [Utils.deviceUniqueId] to get the platform specific unique device identifier for mobile devices
    @required String clientId,

    /// For a secure connection, a secureCertificate file is also required
    /// On a mobile device, the certificate file can be stored in the /assets folder,
    /// and accessed using the Helper method [Utils.getFileFromAssets]
    @required File secureCertificate,
    bool enableLogs = false,
    Duration timeOut = DEFAULT_TIMEOUT,
  }) =>
      EzMqttClient._(
          url: url,
          port: port,
          clientId: clientId,
          secure: true,
          secureCertificate: secureCertificate,
          timeOut: timeOut);

  EzMqttClient._({
    @required this.url,
    @required this.port,
    this.clientId = '',
    this.secure = false,
    this.enableLogs = false,
    this.secureCertificate,
    this.timeOut = DEFAULT_TIMEOUT,
  })  : this._client = MqttServerClient(url, clientId),
        assert(clientId != null),
        assert(!secure || (secureCertificate != null && clientId.isNotEmpty),
            'For a secure connection also provide a valid clientId and a secure certificate file') {
    final keepAliveTime = (timeOut * 0.75);

    _client.logging(on: enableLogs);
    _client.port = port;

    if (secure) {
      _client.secure = true;
      final context = SecurityContext.defaultContext;
      try {
        context.setTrustedCertificates(secureCertificate.absolute.path);
      } on TlsException catch (error) {
        print('[$TAG] ${error.osError.message}');
      }
    }

    _client.keepAlivePeriod = keepAliveTime.inSeconds;

    //ignore bad certificate error
    _client.onBadCertificate = (dynamic value) => true;

    _client.onConnected = _onConnected;

    _client.autoReconnect = true;

    // if the URL is uses a WebSocket scheme, then use the WebSockets transport
    // instead of the default TCP
    if (url.startsWith("ws") || url.startsWith("wss"))
      _client.useWebSocket = true;

    _client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .keepAliveFor(keepAliveTime.inSeconds);
  }

  //************************ Public Methods ************************************

  @override
  Future<bool> connect({String username, String password}) async {
    assert(
        (username == null && password == null) ||
            (username != null && password != null),
        'You need to provide both username and password for authentication.'
        'If you do need authentication using username and password, then keep'
        'both username and password null');

    return await _client
        .connect(username, password)
        .then((status) {
          _updatesStreamSubscription =
              _client.updates.listen(_onMessageReceived);
          _publishedStreamSubscription = _client.published.listen(_onPublished);
          _client.onSubscribed = _onSubscribed;
          _client.onSubscribeFail = _onSubscriptionFailed;

          _cachedUserName = username;
          _cachedPassword = password;

          _didTimeOut = false;

          return true;
        })
        .timeout(timeOut,
            onTimeout: () => _onTimeout("Unable to connect to client."))
        .catchError((error) {
          _client.disconnect();
          throw error;
        });
  }

  @override
  Future<void> disconnect() async {
    _topicSubscriptions
        .forEach((topic, callback) => _client.unsubscribe(topic));
    _topicSubscriptions.clear();
    await _updatesStreamSubscription.cancel();
    await _publishedStreamSubscription.cancel();

    _client.disconnect();
    print('[$TAG] disconnected');
  }

  void resetConnection() {
    _client.disconnect();
  }

  @override
  Future<Message> publishMessage({
    @required String topic,
    @required String message,
    MqttQos qosLevel = MqttQos.exactlyOnce,
  }) async {
    final timeOutMsg =
        "Unable to publish message.\n** Message: $message\n** Topic: $topic";
    await _ensureConnected()
        .timeout(timeOut, onTimeout: () => _onTimeout<bool>(timeOutMsg))
        .catchError((error) {
      throw error;
    });

    var completer;
    // do not over write the completer in the _publishedMessageRequests map if a
    // same message exists with the same topic. Reuse the completer.
    if (_publishedMessageRequests
        .containsKey(_generateMapKey(topic, message))) {
      completer = _publishedMessageRequests[_generateMapKey(topic, message)];
    } else {
      completer = Completer<Message>();
      _publishedMessageRequests[_generateMapKey(topic, message)] = completer;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    try {
      _client.publishMessage(topic, qosLevel, builder.payload);
    } on SocketException catch (_) {
      rethrow;
    } on Exception catch (error) {
      print('[$TAG][publishMessage] error: $error');
    }

    return await completer.future
        .timeout(timeOut, onTimeout: () => _onTimeout<Message>(timeOutMsg));
  }

  @override
  Future<bool> subscribeToTopic(
      {@required String topic,
      @required MessageReceivedCallback onMessage,
      MqttQos qosLevel = MqttQos.exactlyOnce}) async {
    final timeOutMsg = "Unable to to subscribe to topic: $topic";

    await _ensureConnected()
        .timeout(timeOut, onTimeout: () => _onTimeout(timeOutMsg))
        .catchError((error) {
      throw error;
    });

    final completer = Completer<bool>();
    _topicSubscriptionRequests[topic] = completer;
    _topicSubscriptions[topic] = onMessage;
    try {
      _client.subscribe(topic, qosLevel);
    } on Exception catch (error) {
      print('[$TAG][publishMessage] error: $error');
      completer.completeError(error);
    }

    return await completer.future
        .timeout(timeOut, onTimeout: () => _onTimeout<bool>(timeOutMsg));
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    await _ensureConnected().timeout(timeOut).catchError((error) {
      throw error;
    });

    _client.unsubscribe(topic);

    if (!_topicSubscriptions.containsKey(topic)) {
      _topicSubscriptions.remove(topic);
    }
  }

  //************************ Private Methods ***********************************

  Future<bool> _ensureConnected() async {
    if (_didTimeOut) _client.disconnect();

    switch (_client.connectionStatus.state) {
      case MqttConnectionState.connected:
        return true;
      case MqttConnectionState.connecting:
        if (_onConnectedCompleter == null) {
          _onConnectedCompleter = Completer<bool>();
        }
        return _onConnectedCompleter.future;
      case MqttConnectionState.faulted:
        return _reconnect();
      case MqttConnectionState.disconnecting:
        await Future.delayed(Duration(seconds: 1));
        return _reconnect();
      case MqttConnectionState.disconnected:
        return _reconnect();
      default:
        return false;
    }
  }

  Future<bool> _reconnect() async {
    print('[$TAG] reconnecting');
    return await connect(username: _cachedUserName, password: _cachedPassword);
  }

  void _onConnected() {
    print('[$TAG] connected');
    if (_onConnectedCompleter != null && !_onConnectedCompleter.isCompleted) {
      _onConnectedCompleter.complete(true);
      Future.delayed(Duration(seconds: 2), () => _onConnectedCompleter = null);
    }
  }

  void _onMessageReceived(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final message in messages) {
      final MqttPublishMessage recMsg = message.payload;
      final payload =
          MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);

      if (_topicSubscriptions.containsKey(message.topic)) {
        _topicSubscriptions[message.topic](message.topic, payload);
      }
    }
  }

  void _onPublished(MqttPublishMessage message) {
    final topic = message.variableHeader.topicName;
    final payload =
        MqttPublishPayload.bytesToStringAsString(message.payload.message);

    final key = _generateMapKey(topic, payload);

    if (_publishedMessageRequests.containsKey(key) &&
        !_publishedMessageRequests[key].isCompleted) {
      _publishedMessageRequests[key].complete(Message(topic, payload));
      _publishedMessageRequests.remove(key);
    }
  }

  void _onSubscribed(String topic) {
    if (_topicSubscriptionRequests.containsKey(topic) &&
        !_topicSubscriptionRequests[topic].isCompleted) {
      _topicSubscriptionRequests[topic].complete(true);
      _topicSubscriptionRequests.remove(topic);
    }
  }

  void _onSubscriptionFailed(String topic) {
    if (_topicSubscriptionRequests.containsKey(topic) &&
        !_topicSubscriptionRequests[topic].isCompleted) {
      _topicSubscriptionRequests[topic]
          .completeError(Exception("Unable to subscribe to topic $topic"));
      _topicSubscriptionRequests.remove(topic);
      _topicSubscriptions.remove(topic);
    }
  }

  FutureOr<T> _onTimeout<T>(String msg) async {
    _didTimeOut = true;
    throw TimeoutException(msg);
  }

  //********************* Private Static Methods *******************************

  /// Method to create a key for the [_publishedMessageRequests] map.
  /// Format of the key is 'topic##message'
  static String _generateMapKey(String topic, String message) =>
      '$topic##$message';
}
