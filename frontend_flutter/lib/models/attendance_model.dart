class AttendanceModel {
  final String id;
  final String studentId;
  final DateTime date;
  final bool present;

  AttendanceModel({
    required this.id,
    required this.studentId,
    required this.date,
    required this.present,
  });

  factory AttendanceModel.fromMap(Map<String, dynamic> data) {
    return AttendanceModel(
      id: data['id'],
      studentId: data['studentId'],
      date: DateTime.parse(data['date']),
      present: data['present'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'studentId': studentId,
      'date': date.toIso8601String(),
      'present': present,
    };
  }
}