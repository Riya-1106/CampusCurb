class RewardModel {
  final String id;
  final String studentId;
  final String rewardType;
  final int points;
  final DateTime dateEarned;

  RewardModel({
    required this.id,
    required this.studentId,
    required this.rewardType,
    required this.points,
    required this.dateEarned,
  });

  factory RewardModel.fromMap(Map<String, dynamic> data) {
    return RewardModel(
      id: data['id'],
      studentId: data['studentId'],
      rewardType: data['rewardType'],
      points: data['points'],
      dateEarned: DateTime.parse(data['dateEarned']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'studentId': studentId,
      'rewardType': rewardType,
      'points': points,
      'dateEarned': dateEarned.toIso8601String(),
    };
  }
}