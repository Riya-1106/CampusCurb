import React from "react";
import { View, Text, StyleSheet } from "react-native";
import colors from "../../theme/colors";

export default function LeaderboardScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.heading}>Leaderboard</Text>

      <View style={styles.card}>
        <Text>🥇 Riya - 300 pts</Text>
        <Text>🥈 Arjun - 250 pts</Text>
        <Text>🥉 Meera - 200 pts</Text>
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
