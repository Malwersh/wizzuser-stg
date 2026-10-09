// File: lib/models/session_state.dart

abstract class SessionState {}

class SessionInitial extends SessionState {}

class SessionActive extends SessionState {
  final Map<String, dynamic> userData;
  SessionActive(this.userData);
}

class GuestSession extends SessionState {}

class SessionExpired extends SessionState {}
