import React from "react";
import { createBottomTabNavigator } from "@react-navigation/bottom-tabs";

import StudentDashboard from "../screens/student/StudentDashboard";
import MenuScreen from "../screens/student/MenuScreen";
import FeedbackScreen from "../screens/student/FeedbackScreen";
import RewardsScreen from "../screens/student/RewardsScreen";
import LeaderboardScreen from "../screens/student/LeaderboardScreen";
import NotificationScreen from "../screens/student/NotificationScreen";

const Tab = createBottomTabNavigator();

export default function StudentTabs() {
  return (
    <Tab.Navigator>
      <Tab.Screen name="Home" component={StudentDashboard} />
      <Tab.Screen name="Menu" component={MenuScreen} />
      <Tab.Screen name="Feedback" component={FeedbackScreen} />
      <Tab.Screen name="Rewards" component={RewardsScreen} />
      <Tab.Screen name="Leaders" component={LeaderboardScreen} />
      <Tab.Screen name="Notify" component={NotificationScreen} />
    </Tab.Navigator>
  );
}
