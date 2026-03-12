class PredictionModel {
  final String id;
  final String itemName;
  final int predictedQuantity;
  final DateTime date;

  PredictionModel({
    required this.id,
    required this.itemName,
    required this.predictedQuantity,
    required this.date,
  });

  factory PredictionModel.fromMap(Map<String, dynamic> data) {
    return PredictionModel(
      id: data['id'],
      itemName: data['itemName'],
      predictedQuantity: data['predictedQuantity'],
      date: DateTime.parse(data['date']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'itemName': itemName,
      'predictedQuantity': predictedQuantity,
      'date': date.toIso8601String(),
    };
  }
}