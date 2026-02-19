import React from "react";
import { View, Text, StyleSheet } from "react-native";
import colors from "../../theme/colors";

export default function RewardsScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.heading}>Your Rewards</Text>

      <View style={styles.card}>
        <Text>⭐ Total Points: 120</Text>
        <Text>🏆 Rank: 5</Text>
      </View>

      <View style={styles.card}>
        <Text>🎁 Redeem Options</Text>
        <Text>- Free Dessert</Text>
        <Text>- Extra Meal Coupon</Text>
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
    marginBottom: 15,
  },
});
