import 'package:flutter_test/flutter_test.dart';
import 'package:lumii_quest/features/friends/domain/relationship_status.dart';

void main() {
  test('maps relationship states returned by Supabase', () {
    expect(
      RelationshipStatus.fromDatabase('outgoing_pending'),
      RelationshipStatus.outgoingPending,
    );
    expect(
      RelationshipStatus.fromDatabase('incoming_pending'),
      RelationshipStatus.incomingPending,
    );
    expect(
      RelationshipStatus.fromDatabase('friends'),
      RelationshipStatus.friends,
    );
  });
}
