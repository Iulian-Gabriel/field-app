# Field app

Team: Cheoseaua Iulian-Gabriel, Boroș Gabriela-Costina

One repository, two stacks: `expo/` (React Native) and `flutter/` (Flutter).
Screenshots of both apps on web, emulator and phone are in `docs/week-1/`.

## Run the Expo app

    cd expo
    bun install
    bun run web        # browser
    bun start          # press a for the emulator, or scan the QR code with Expo Go

## Run the Flutter app

    cd flutter
    flutter pub get
    flutter run -d edge                  # web (or chrome)
    flutter run -d emulator-5554         # Android emulator
    flutter run -d <serial>              # phone, serial from `flutter devices`

## Requirements

Node 20+, Bun, Git, Android Studio (SDK + JDK 17/21), Flutter 3.47.

## Firebase project ID

field-app-iulian-tina