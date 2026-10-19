import React from 'react';
import {
  Button,
  PixelRatio,
  Platform,
  StyleSheet,
  Text,
  TextProps,
  View,
  useWindowDimensions,
} from 'react-native';
import * as Device from 'expo-device';
import {
  NavigationContainer,
  DefaultTheme,
  DarkTheme,
  useTheme,
} from '@react-navigation/native';
import {
  createNativeStackNavigator,
  NativeStackScreenProps,
} from '@react-navigation/native-stack';
import { SafeAreaProvider, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useColorScheme } from 'react-native';

/* ---------- Model ---------- */

type Building = {
  id: string;
  address: string;
  floors?: number; // undefined = not surveyed yet
  elevators?: number;
};

function describe(b: Building): string {
  const floors = b.floors ?? 'unknown';
  const elevators = b.elevators ?? 'unknown';
  if (b.elevators == null) {
    return `${b.address}: ${floors} floors, elevators ${elevators}`;
  }
  return `${b.address}: ${floors} floors, ${elevators} elevators`;
}

/* ---------- Device info ---------- */

type DeviceInfo = { os: string; model: string };

function loadDeviceInfo(): DeviceInfo {
  if (Platform.OS === 'web') {
    return {
      os: 'n/a (running in a browser)',
      model: 'n/a (web)',
    };
  }
  if (Platform.OS === 'android') {
    return {
      os: `Android ${Device.osVersion} (API ${Platform.Version})`,
      model: `${Device.manufacturer} ${Device.modelName}`,
    };
  }
  if (Platform.OS === 'ios') {
    return {
      os: `${Device.osName} ${Device.osVersion}`,
      model: Device.modelId ?? 'unknown', // e.g. "iPhone14,2"
    };
  }
  return { os: 'n/a', model: 'n/a' };
}

/* ---------- Shared bits ---------- */

// Text that follows the navigation theme (light/dark)
function T(props: TextProps) {
  const { colors } = useTheme();
  return <Text {...props} style={[{ color: colors.text }, props.style]} />;
}

type RootStackParamList = {
  Home: undefined;
  DeviceInfo: undefined;
};

const Stack = createNativeStackNavigator<RootStackParamList>();

/* ---------- Screens ---------- */

function HomeScreen({ navigation }: NativeStackScreenProps<RootStackParamList, 'Home'>) {
  const b: Building = { id: 'b-17', address: 'Str. Lipscani 12' };

  return (
    <View style={styles.center}>
      <T>Hello from Expo on {Platform.OS}</T>
      <T>{describe(b)}</T>
      <View style={{ height: 16 }} />
      <Button title="Device info" onPress={() => navigation.navigate('DeviceInfo')} />
    </View>
  );
}

function DeviceInfoScreen() {
  const { width, height } = useWindowDimensions();
  const ratio = PixelRatio.get();
  const orientation = width > height ? 'landscape' : 'portrait';
  const dark = useColorScheme() === 'dark';
  const pad = useSafeAreaInsets();
  const info = React.useMemo(loadDeviceInfo, []);

  return (
    <View style={[styles.padded, { paddingTop: 16 + pad.top, paddingBottom: 16 + pad.bottom }]}>
      <T>Platform: {Platform.OS}</T>
      <T>OS version: {info.os}</T>
      <T>
        Screen: {Math.round(width)} x {Math.round(height)} logical px
      </T>
      <T>Pixel ratio: {ratio.toFixed(2)}</T>
      <T>Model: {info.model}</T>
      <T>Orientation: {orientation}</T>
      <T>Dark mode: {dark ? 'yes' : 'no'}</T>
      <T>
        Safe Area: top {Math.round(pad.top)}, bottom {Math.round(pad.bottom)}
      </T>
    </View>
  );
}

/* ---------- App ---------- */

export default function App() {
  const scheme = useColorScheme();

  return (
    <SafeAreaProvider>
      <NavigationContainer theme={scheme === 'dark' ? DarkTheme : DefaultTheme}>
        <Stack.Navigator>
          <Stack.Screen name="Home" component={HomeScreen} options={{ title: 'Field app' }} />
          <Stack.Screen
            name="DeviceInfo"
            component={DeviceInfoScreen}
            options={{ title: 'Device info' }}
          />
        </Stack.Navigator>
      </NavigationContainer>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  padded: { flex: 1, paddingHorizontal: 16 },
});
