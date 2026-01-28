# ProtoLog 🧬

ProtoLog is a tracking application built with **Flutter** designed for managing and visualizing protocols for anabolic compounds, peptides, and ancillaries. It features an Pharmacokinetic (PK) plotter to estimate active blood serum levels over time.

## 🚀 Features

- **Advanced PK Plotter:**
    - Visualizes ester release curves using the Bateman equation.
    - Supports complex mixes like **Sustanon**.
    - **Dual-Axis Graphing:** Scales oral steroids separately from injectables for better visibility.
    - **Peptide Swimlanes:** Tracks active windows for peptides with fading saturation bars or simple event markers.
- **Comprehensive Logging:**
    - Track Steroids (Injectable/Oral), Peptides, and Ancillaries.
    - Volume Calculator (mg/ml to dose).
    - Precise Date & Time logging.
- **Compound Library:**
    - Pre-loaded library with accurate half-lives and ester weights.
    - Create custom compounds with specific graph behaviors (Curve, Active Window, or Event).
- **Data Persistence:** Automatically saves your history and custom library locally.

## 🛠️ Project Structure

- `lib/main.dart`: Core UI logic, navigation, graph painting, and state management.
- `lib/data.dart`: Static database of compounds, esters, and default values.
- `lib/models.dart`: Data models (JSON serialization) and type definitions.

## 📦 Getting Started

1. **Prerequisites:** Ensure you have the [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.
2. **Install Dependencies:**
    
    ```
    flutter pub get
    
    ```
    
3. **Run the App:**
    
    ```
    flutter run
    
    ```
    
    *For a release build on Android:*
    
    ```
    flutter run --release
    
    ```
    

## 📱 Dependencies

- `flutter`: SDK
- `shared_preferences`: Local storage for persistence.
- `flutter_launcher_icons`: (Dev) For generating app icons.

## 🎨 Customization

To modify default compounds, edit `BASE_LIBRARY` in `lib/data.dart`.
To adjust graph physics (half-life calculations), check the `PKEngine` class in `lib/main.dart`.