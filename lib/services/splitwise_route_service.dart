import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'mysql_service.dart';

class SplitwiseRouteService {
  SplitwiseRouteService({
    http.Client? client,
    MySqlService? mySqlService,
  })  : _client = client ?? http.Client(),
        _mySqlService = mySqlService ?? MySqlService();

  final http.Client _client;
  final MySqlService _mySqlService;

  Future<Map<String, dynamic>> _fetchSplitwise(
    String endpoint,
    String apiKey,
  ) async {
    final url = Uri.parse('https://secure.splitwise.com/api/v3.0/$endpoint');
    final response = await _client.get(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      Map<String, dynamic> errorBody = {'error': 'Failed to parse error body'};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          errorBody = decoded;
        }
      } catch (_) {}

      debugPrint(
        'Splitwise API error for endpoint $endpoint: '
        'status=${response.statusCode}, body=$errorBody',
      );
      throw Exception(
        'Splitwise API request failed with status ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const FormatException('Unexpected Splitwise response format');
  }

  Future<List<SplitwiseGroup>> getGroupsWithMembers() async {
    final splitwiseApiKey = dotenv.env['SPLITWISE_API_KEY']?.trim() ?? '';
    if (splitwiseApiKey.isEmpty) {
      throw StateError('Splitwise API key is not configured.');
    }

    final config = MySqlConfig.fromDotEnv();
    await _mySqlService.connect(config);

    try {
      final dbFriendsResult = await _mySqlService.executeReadQuery(
        'SELECT ID, SPLITWISE_FRIEND_ID, NAME FROM SplitwiseFriends',
      );

      final splitwiseFriendIdToDbId = <String, int>{};
      final dbFriendsRows = (dbFriendsResult['rows'] as List? ?? []);
      for (final row in dbFriendsRows) {
        final rowMap = Map<String, dynamic>.from(row as Map);
        final splitwiseFriendId = rowMap['SPLITWISE_FRIEND_ID']?.toString();
        final dbId = int.tryParse(rowMap['ID']?.toString() ?? '');
        if (splitwiseFriendId != null && splitwiseFriendId.isNotEmpty && dbId != null) {
          splitwiseFriendIdToDbId[splitwiseFriendId] = dbId;
        }
      }

      final groupsResponse = await _fetchSplitwise('get_groups', splitwiseApiKey);
      final rawGroups = (groupsResponse['groups'] as List? ?? []);

      final groupsWithMembers = <SplitwiseGroup>[];
      for (final groupItem in rawGroups) {
        final groupMap = Map<String, dynamic>.from(groupItem as Map);
        final groupId = groupMap['id']?.toString();
        if (groupId == null || groupId.isEmpty) {
          continue;
        }

        final groupDetails = await _fetchSplitwise(
          'get_group/$groupId',
          splitwiseApiKey,
        );

        final groupPayload = groupDetails['group'];
        final membersRaw = groupPayload is Map<String, dynamic>
            ? (groupPayload['members'] as List? ?? [])
            : <dynamic>[];

        final members = membersRaw.map((memberItem) {
          final memberMap = Map<String, dynamic>.from(memberItem as Map);
          final memberId = memberMap['id']?.toString() ?? '';
          final firstName = memberMap['first_name']?.toString() ?? '';
          final lastName = memberMap['last_name']?.toString() ?? '';
          final fullName = '$firstName $lastName'.trim();

          return SplitwiseMember(
            id: memberId,
            friendId: (splitwiseFriendIdToDbId[memberId] ?? '').toString(),
            name: fullName,
          );
        }).toList();

        groupsWithMembers.add(
          SplitwiseGroup(
            id: groupId,
            name: groupMap['name']?.toString() ?? '',
            members: members,
          ),
        );
      }

      return groupsWithMembers;
    } catch (error) {
      debugPrint('Error fetching Splitwise data: $error');
      rethrow;
    } finally {
      await _mySqlService.disconnect();
    }
  }
}
