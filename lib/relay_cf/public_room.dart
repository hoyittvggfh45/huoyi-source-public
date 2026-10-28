import 'cf_relay_client.dart';
import 'cf_relay_constants.dart';

Future<CfRelayClient> joinPublicRoom({
  required String baseUrl,
  required String deviceId,
}) async {
  final client = CfRelayClient();
  await client.connect(
    url: baseUrl,
    channelId: cfPublicRoomId,
    senderId: deviceId,
  );
  return client;
}
