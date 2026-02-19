import React, { useState } from "react";
import { View, Text, TextInput, Button, StyleSheet } from "react-native";
import colors from "../../theme/colors";

export default function FeedbackScreen() {
  const [feedback, setFeedback] = useState("");

  return (
    <View style={styles.container}>
      <Text style={styles.heading}>Food Feedback</Text>

      <TextInput
        style={styles.input}
        placeholder="Write your feedback..."
        value={feedback}
        onChangeText={setFeedback}
        multiline
      />

      <Button title="Submit Feedback" onPress={() => alert("Submitted!")} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 20, backgroundColor: colors.background },
  heading: { fontSize: 22, fontWeight: "bold", marginBottom: 20 },
  input: {
    backgroundColor: colors.white,
    padding: 15,
    borderRadius: 10,
    height: 120,
    marginBottom: 20,
  },
});
