enum RelationshipStatus {
  signedOut,
  self,
  none,
  outgoingPending,
  incomingPending,
  friends;

  static RelationshipStatus fromDatabase(String? value) {
    return switch (value) {
      'self' => RelationshipStatus.self,
      'none' => RelationshipStatus.none,
      'outgoing_pending' => RelationshipStatus.outgoingPending,
      'incoming_pending' => RelationshipStatus.incomingPending,
      'friends' => RelationshipStatus.friends,
      _ => RelationshipStatus.signedOut,
    };
  }
}
