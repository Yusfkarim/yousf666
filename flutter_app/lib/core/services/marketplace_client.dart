import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _tokenKey = 'yousf_api_token';
const _apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://100.112.174.17:8081');

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LocalUser {
  const LocalUser({required this.id, this.email});
  final String id;
  final String? email;
}

class LocalSession {
  const LocalSession({required this.accessToken, required this.user});
  final String accessToken;
  final LocalUser user;
}

class AuthState {
  const AuthState({this.session});
  final LocalSession? session;
}

class AuthResponse {
  const AuthResponse({this.session});
  final LocalSession? session;
}

class FileOptions {
  const FileOptions({this.contentType, this.upsert = false});
  final String? contentType;
  final bool upsert;
}

enum PostgresChangeEvent { insert, update, delete, all }

enum PostgresChangeFilterType { eq }

class PostgresChangeFilter {
  const PostgresChangeFilter({required this.type, required this.column, required this.value});
  final PostgresChangeFilterType type;
  final String column;
  final Object value;
}

enum OAuthProvider { google }

class LocalChannel {
  LocalChannel(this._client, this._name);

  final MarketplaceClient _client;
  final String _name;
  Timer? _timer;
  bool _closed = false;

  LocalChannel onPostgresChanges({
    required PostgresChangeEvent event,
    String? schema,
    required String table,
    PostgresChangeFilter? filter,
    required void Function(dynamic) callback,
  }) {
    if (_closed) return this;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_closed) callback(<String, dynamic>{'table': table, 'eventType': event.name});
    });
    return this;
  }

  LocalChannel subscribe() => this;

  Future<void> unsubscribe() async {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _client._channels.remove(_name);
  }
}

class LocalStorageBucket {
  LocalStorageBucket(this._client, this.name);

  final MarketplaceClient _client;
  final String name;

  Future<String> uploadBinary(String path, List<int> bytes, {FileOptions? fileOptions}) async {
    final response = await _client._send(
      'PUT',
      '/storage/v1/object/$name/$path',
      body: bytes,
      contentType: fileOptions?.contentType ?? 'application/octet-stream',
    );
    if (response.statusCode >= 400) {
      throw ApiException(_message(response.body));
    }
    return '$_apiUrl/storage/v1/object/public/$name/$path';
  }

  String getPublicUrl(String path) => '$_apiUrl/storage/v1/object/public/$name/$path';
}

class LocalStorage {
  LocalStorage(this._client);
  final MarketplaceClient _client;
  LocalStorageBucket from(String bucket) => LocalStorageBucket(_client, bucket);
}

class LocalAuth {
  final MarketplaceClient _client;
  final StreamController<AuthState> _controller = StreamController<AuthState>.broadcast();
  LocalUser? _currentUser;
  String? _token;

  LocalAuth(this._client);

  Stream<AuthState> get onAuthStateChange => _controller.stream;
  LocalUser? get currentUser => _currentUser;
  String? get token => _token;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_tokenKey);
    if (saved == null || saved.isEmpty) return;
    _token = saved;
    try {
      final response = await _client._send('GET', '/auth/v1/user');
      if (response.statusCode >= 400) throw ApiException(_message(response.body));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _currentUser = LocalUser(id: '${data['id']}', email: data['email'] as String?);
      _controller.add(AuthState(session: LocalSession(accessToken: saved, user: _currentUser!)));
    } catch (_) {
      await signOut();
    }
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    final response = await _client._send(
      'POST',
      '/auth/v1/signup',
      body: utf8.encode(jsonEncode({
        'email': email,
        'password': password,
        'data': data ?? const <String, dynamic>{},
      })),
      contentType: 'application/json',
    );
    if (response.statusCode >= 400) throw AuthException(_message(response.body));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final token = payload['access_token'] as String?;
    if (token == null) return const AuthResponse(session: null);
    await _save(token);
    final user = payload['user'] as Map<String, dynamic>;
    _currentUser = LocalUser(id: '${user['id']}', email: user['email'] as String?);
    final session = LocalSession(accessToken: token, user: _currentUser!);
    _controller.add(AuthState(session: session));
    return AuthResponse(session: session);
  }

  Future<void> signInWithPassword({required String email, required String password}) async {
    final response = await _client._send(
      'POST',
      '/auth/v1/token?grant_type=password',
      body: utf8.encode(jsonEncode({'email': email, 'password': password})),
      contentType: 'application/json',
    );
    if (response.statusCode >= 400) throw AuthException(_message(response.body));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final token = payload['access_token'] as String;
    await _save(token);
    final user = payload['user'] as Map<String, dynamic>;
    _currentUser = LocalUser(id: '${user['id']}', email: user['email'] as String?);
    _controller.add(AuthState(session: LocalSession(accessToken: token, user: _currentUser!)));
  }

  Future<void> signInWithOAuth(OAuthProvider provider, {String? redirectTo}) async {
    throw const AuthException('چوونەژوورەوە بە گووگڵ لەم وەشانە ناوخۆییدا بەردەست نییە.');
  }

  Future<void> signOut() async {
    try {
      await _client._send('POST', '/auth/v1/logout');
    } catch (_) {
      /* local cleanup still applies */
    }
    _token = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    _controller.add(const AuthState(session: null));
  }

  Future<void> _save(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }
}

class LocalQuery implements Future<List<Map<String, dynamic>>> {
  LocalQuery(this._client, this._table);

  final MarketplaceClient _client;
  final String _table;
  final Map<String, String> _params = <String, String>{};
  String _method = 'GET';
  List<int>? _body;
  String _contentType = 'application/json';

  LocalQuery select([String columns = '*']) {
    _params['select'] = columns;
    return this;
  }

  LocalQuery eq(String column, Object value) {
    _params[column] = 'eq.$value';
    return this;
  }

  LocalQuery ilike(String column, String pattern) {
    _params[column] = 'ilike.$pattern';
    return this;
  }

  LocalQuery inFilter(String column, List<Object> values) {
    _params[column] = 'in.(${values.join(',')})';
    return this;
  }

  LocalQuery order(String column, {bool ascending = true}) {
    _params['order'] = '$column.${ascending ? 'asc' : 'desc'}';
    return this;
  }

  LocalQuery limit(int count) {
    _params['limit'] = '$count';
    return this;
  }

  LocalQuery range(int from, int to) {
    _params['offset'] = '$from';
    _params['limit'] = '${to - from + 1}';
    return this;
  }

  LocalQuery insert(Map<String, dynamic> value) {
    _method = 'POST';
    _body = utf8.encode(jsonEncode(value));
    return this;
  }

  LocalQuery update(Map<String, dynamic> value) {
    _method = 'PATCH';
    _body = utf8.encode(jsonEncode(value));
    return this;
  }

  LocalQuery delete() {
    _method = 'DELETE';
    return this;
  }

  Future<List<Map<String, dynamic>>> _run() async {
    final uri = Uri.parse('$_apiUrl/rest/v1/$_table').replace(queryParameters: _params);
    final response = await _client._send(
      _method,
      '/rest/v1/$_table${uri.hasQuery ? '?${uri.query}' : ''}',
      body: _body,
      contentType: _contentType,
      prefer: 'return=minimal',
    );
    if (response.statusCode >= 400) throw ApiException(_message(response.body));
    if (response.body.trim().isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return <Map<String, dynamic>>[];
    return decoded.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<Map<String, dynamic>> single() async {
    final rows = await _run();
    if (rows.isEmpty) throw const ApiException('هیچ داتایەک نەدۆزرایەوە.');
    return rows.first;
  }

  Future<Map<String, dynamic>?> maybeSingle() async {
    final rows = await _run();
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {Function? onError}) {
    return _run().then<R>(onValue, onError: onError as FutureOr<R> Function(Object)?);
  }

  @override
  Future<List<Map<String, dynamic>>> catchError(Function onError, {bool test(Object error)? = null}) {
    return _run().catchError(onError, test: test);
  }

  @override
  Future<List<Map<String, dynamic>>> whenComplete(FutureOr<void> Function() action) {
    return _run().whenComplete(action);
  }

  @override
  Future<List<Map<String, dynamic>>> timeout(Duration timeLimit, {FutureOr<List<Map<String, dynamic>>> Function()? onTimeout}) {
    return _run().timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Stream<List<Map<String, dynamic>>> asStream() => _run().asStream();
}

class MarketplaceClient {
  MarketplaceClient({this.baseUrl = _apiUrl});

  final String baseUrl;
  final Map<String, LocalChannel> _channels = <String, LocalChannel>{};
  late final LocalAuth auth = LocalAuth(this);
  late final LocalStorage storage = LocalStorage(this);

  LocalQuery from(String table) => LocalQuery(this, table);

  Future<Object?> rpc(String name, {Map<String, dynamic>? params}) async {
    final response = await _send(
      'POST',
      '/rest/v1/rpc/$name',
      body: utf8.encode(jsonEncode(params ?? const <String, dynamic>{})),
      contentType: 'application/json',
    );
    if (response.statusCode >= 400) throw ApiException(_message(response.body));
    if (response.body.trim().isEmpty) return null;
    return jsonDecode(response.body);
  }

  LocalChannel channel(String name) {
    final existing = _channels[name];
    if (existing != null) return existing;
    final channel = LocalChannel(this, name);
    _channels[name] = channel;
    return channel;
  }

  Future<void> removeChannel(LocalChannel channel) => channel.unsubscribe();

  Future<http.Response> _send(
    String method,
    String path, {
    List<int>? body,
    String contentType = 'application/json',
    String? prefer,
  }) {
    final headers = <String, String>{
      'apikey': 'local-anon-key',
      'content-type': contentType,
    };
    final token = auth.token;
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    if (prefer != null) headers['Prefer'] = prefer;
    final uri = Uri.parse('$baseUrl$path');
    switch (method) {
      case 'POST':
        return http.post(uri, headers: headers, body: body);
      case 'PATCH':
        return http.patch(uri, headers: headers, body: body);
      case 'PUT':
        return http.put(uri, headers: headers, body: body);
      case 'DELETE':
        return http.delete(uri, headers: headers);
      default:
        return http.get(uri, headers: headers);
    }
  }
}

String _message(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['message'] != null) return '${decoded['message']}';
    if (decoded is Map && decoded['error'] is Map && decoded['error']['message'] != null) {
      return '${decoded['error']['message']}';
    }
  } catch (_) {
    /* fall through */
  }
  return body.isEmpty ? 'داواکاری شکستی هێنا.' : body;
}

final appClient = MarketplaceClient();
