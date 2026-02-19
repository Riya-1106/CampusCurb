import React from "react";
import { View, Text, StyleSheet } from "react-native";
import colors from "../../theme/colors";

export default function StudentDashboard() {
  return (
    <View style={styles.container}>
      <Text style={styles.heading}>Welcome 👋</Text>

      <View style={styles.card}>
        <Text style={styles.title}>Today's Smart Prediction</Text>
        <Text>🍚 Rice: 120 plates</Text>
        <Text>🥘 Curry: 95 plates</Text>
        <Text>🥗 Salad: 60 plates</Text>
      </View>

      <View style={styles.card}>
        <Text style={styles.title}>Your Impact</Text>
        <Text>🌱 Waste Saved: 2.3 kg</Text>
        <Text>⭐ Points Earned: 120</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
    padding: 20,
  },
  heading: {
    fontSize: 24,
    fontWeight: "bold",
    marginBottom: 20,
  },
  card: {
    backgroundColor: colors.white,
    padding: 15,
    borderRadius: 10,
    marginBottom: 15,
  },
  title: {
    fontWeight: "bold",
    marginBottom: 8,
  },
});
