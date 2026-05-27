import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static final LocalStorageService _instance = LocalStorageService._internal();
  factory LocalStorageService() => _instance;
  LocalStorageService._internal();

  static const String _keyAccounts = 'cached_accounts';
  static const String _keyCategories = 'cached_categories';
  static const String _keyCreditCardCaps = 'cached_credit_card_caps';
  static const String _keySplitwiseGroups = 'cached_splitwise_groups';
  static const String _keyInvestmentAccounts = 'cached_investment_accounts';
  static const String _keySessionCookie = 'session_cookie';
  static const String _keyUsername = 'session_username';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ─── Save Methods ──────────────────────────────────────────

  Future<void> saveAccounts(Map<String, dynamic> data) async {
    final prefs = await _preferences;
    await prefs.setString(_keyAccounts, jsonEncode(data));
    debugPrint('[LocalStorage] Saved accounts');
  }

  Future<void> saveCategories(Map<String, dynamic> data) async {
    final prefs = await _preferences;
    await prefs.setString(_keyCategories, jsonEncode(data));
    debugPrint('[LocalStorage] Saved categories');
  }

  Future<void> saveCreditCardCaps(Map<String, dynamic> data) async {
    final prefs = await _preferences;
    await prefs.setString(_keyCreditCardCaps, jsonEncode(data));
    debugPrint('[LocalStorage] Saved credit card caps');
  }

  Future<void> saveSplitwiseGroups(Map<String, dynamic> data) async {
    final prefs = await _preferences;
    await prefs.setString(_keySplitwiseGroups, jsonEncode(data));
    debugPrint('[LocalStorage] Saved splitwise groups');
  }

  Future<void> saveInvestmentAccounts(List<dynamic> data) async {
    final prefs = await _preferences;
    await prefs.setString(_keyInvestmentAccounts, jsonEncode(data));
    debugPrint('[LocalStorage] Saved investment accounts');
  }

  // ─── Load Methods ──────────────────────────────────────────

  Future<Map<String, dynamic>?> loadAccounts() async {
    final prefs = await _preferences;
    final raw = prefs.getString(_keyAccounts);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> loadCategories() async {
    final prefs = await _preferences;
    final raw = prefs.getString(_keyCategories);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> loadCreditCardCaps() async {
    final prefs = await _preferences;
    final raw = prefs.getString(_keyCreditCardCaps);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> loadSplitwiseGroups() async {
    final prefs = await _preferences;
    final raw = prefs.getString(_keySplitwiseGroups);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<List<dynamic>?> loadInvestmentAccounts() async {
    final prefs = await _preferences;
    final raw = prefs.getString(_keyInvestmentAccounts);
    if (raw == null) return null;
    return jsonDecode(raw) as List<dynamic>;
  }

  // ─── Session / Auth ────────────────────────────────────────

  Future<void> saveSessionCookie(String cookie) async {
    final prefs = await _preferences;
    await prefs.setString(_keySessionCookie, cookie);
  }

  Future<String?> getSessionCookie() async {
    final prefs = await _preferences;
    return prefs.getString(_keySessionCookie);
  }

  Future<void> saveUsername(String username) async {
    final prefs = await _preferences;
    await prefs.setString(_keyUsername, username);
  }

  Future<String?> getUsername() async {
    final prefs = await _preferences;
    return prefs.getString(_keyUsername);
  }

  Future<void> clearSession() async {
    final prefs = await _preferences;
    await prefs.remove(_keySessionCookie);
    await prefs.remove(_keyUsername);
  }

  Future<void> clearAll() async {
    final prefs = await _preferences;
    await prefs.clear();
  }
}
