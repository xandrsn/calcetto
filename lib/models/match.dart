class ActivityEvent {
  final String timestamp;
  final String type;
  final String message;

  const ActivityEvent({
    required this.timestamp,
    required this.type,
    required this.message,
  });

  factory ActivityEvent.fromJson(Map<String, dynamic> j) => ActivityEvent(
    timestamp: j['timestamp'] as String,
    type: j['type'] as String,
    message: j['message'] as String,
  );

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'type': type,
    'message': message,
  };
}

class ChatMessage {
  final String user;
  final String timestamp;
  final String text;

  const ChatMessage({
    required this.user,
    required this.timestamp,
    required this.text,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    user: j['user'] as String,
    timestamp: j['timestamp'] as String,
    text: j['text'] as String,
  );

  Map<String, dynamic> toJson() => {
    'user': user,
    'timestamp': timestamp,
    'text': text,
  };
}
