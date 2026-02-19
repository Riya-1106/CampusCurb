import React from "react";
import { View, Text, StyleSheet } from "react-native";
import colors from "../../theme/colors";

export default function MenuScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.heading}>Today's Menu</Text>

      <View style={styles.card}>
        <Text>🍚 Rice</Text>
        <Text>🥘 Paneer Curry</Text>
        <Text>🥗 Veg Salad</Text>
        <Text>🍩 Dessert</Text>
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
