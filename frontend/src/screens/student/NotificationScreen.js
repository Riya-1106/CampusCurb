import React from "react";
import { View, Text, StyleSheet } from "react-native";
import colors from "../../theme/colors";

export default function NotificationScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.heading}>Notifications</Text>

      <View style={styles.card}>
        <Text>📢 Today's menu updated</Text>
        <Text>🎁 You earned 10 points!</Text>
        <Text>⚠ Food waste reduced by 15%</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 20, backgroundColor: colors.background },
  heading: { fontSize: 22, fontWeight: "bold", marginBottom: 20 },
  card: {
    backgroundColor: colors.white,
    padding: 15,
    borderRadius: 10,
  },
});
