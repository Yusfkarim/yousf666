import 'marketplace_client.dart';
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class PushTokenService {
  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _syncedUserId;
  String? _syncingUserId;

  Future<void> syncCurrentUser(MarketplaceClient client) async {
    final userId = client.auth.currentUser?.id;
    if (kIsWeb || userId == null || _syncedUserId == userId || _syncingUserId == userId) return;
    _syncingUserId = userId;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      if (client.auth.currentUser?.id != userId) return;

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null && client.auth.currentUser?.id == userId) {
        await client.from('profiles').update({'fcm_token': token}).eq('id', userId);
      }

      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen((newToken) async {
        if (client.auth.currentUser?.id != userId) return;
        try {
          await client.from('profiles').update({'fcm_token': newToken}).eq('id', userId);
        } catch (error) {
          debugPrint('FCM token refresh sync failed: $error');
        }
      });
      _syncedUserId = userId;
    } catch (error) {
      // Firebase configuration is optional for local development; auth and in-app realtime remain usable.
      debugPrint('FCM token sync skipped: $error');
    } finally {
      if (_syncingUserId == userId) _syncingUserId = null;
    }
  }

  Future<void> clearCurrentUser() async {
    _syncedUserId = null;
    _syncingUserId = null;
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }

  Future<void> dispose() => clearCurrentUser();
}
