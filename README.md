# 🚗 Ride Monorepo

The Ride project is a monorepo that combines a Flutter mobile client and a Node.js backend service. This README walks through the full setup process on a brand-new Windows 11 machine so a new developer can get productive quickly.

## 🧩 Prerequisites

Before cloning the project, install and configure the following tools:

### Windows 11
* Ensure you have administrator privileges to install software and modify the system PATH.

### Git
1. Download the latest Windows installer from [git-scm.com](https://git-scm.com/download/win).
2. Run the installer and accept the defaults unless you have specific preferences.
3. Configure your global identity after installation:
   ```powershell
   git config --global user.name "Your Name"
   git config --global user.email "your.email@example.com"
   ```

### Node.js and npm
1. Download the latest **LTS** installer from [nodejs.org](https://nodejs.org/).
2. During installation, allow the installer to add Node.js to your PATH.
3. Verify after installation:
   ```powershell
   node -v
   npm -v
   ```

### Flutter SDK
1. Download the Windows Flutter SDK ZIP from [flutter.dev](https://docs.flutter.dev/get-started/install/windows).
2. Extract it to a directory such as `C:\src\flutter` (avoid paths with spaces).
3. Add `C:\src\flutter\bin` to your PATH (see the Environment Setup section).
4. Run `flutter doctor` to verify.

### Android Studio (with SDK + emulator)
1. Download Android Studio from [developer.android.com](https://developer.android.com/studio).
2. Install the Android SDK, SDK Platform Tools, and at least one Android API (e.g., Android 13).
3. Use the Device Manager to create an Android Virtual Device (AVD) for testing.

### Visual Studio Code
1. Install VS Code from [code.visualstudio.com](https://code.visualstudio.com/).
2. In the Extensions marketplace, install:
   * **Flutter** (Dart Code)
   * **Dart**
   * Optionally, **ESLint** or **Prettier** for Node.js development.

### Optional: Visual Studio (Community)
Install [Visual Studio Community](https://visualstudio.microsoft.com/vs/community/) with the "Desktop development with C++" workload if you plan to build Windows desktop binaries for Flutter.

## ⚙️ Environment Setup

### Update the PATH variable
Add the following directories to the system or user PATH so you can run tools from any terminal:
* Flutter: `C:\src\flutter\bin`
* Android platform tools (adb): `C:\Users\<USERNAME>\AppData\Local\Android\Sdk\platform-tools`
* Node.js: `C:\Program Files\nodejs`

**Steps:**
1. Open the Windows **Start** menu and search for "Environment Variables".
2. Click **Edit the system environment variables** → **Environment Variables**.
3. Under *User variables*, select **Path** → **Edit** → **New**, and paste each path above.
4. Re-open any PowerShell or Command Prompt windows so they pick up the new PATH.

### Verify installations
Run the following commands in PowerShell to ensure everything is configured correctly:
```powershell
git --version
node -v
npm -v
flutter doctor
```
`flutter doctor` should report no missing components. If it lists issues, follow the instructions to resolve them (e.g., install Android licenses or accept missing components).

## 🚀 Project Setup

### 1. Clone the repository
Use SSH to clone the repository (replace `USERNAME` and `REPO_NAME` with the correct values):
```powershell
cd C:\path\to\your\projects
git clone git@github.com:USERNAME/REPO_NAME.git
cd REPO_NAME
```

### 2. Install backend dependencies
```powershell
cd backend
npm install
```

### 3. Install frontend dependencies
```powershell
cd ..\frontend
flutter pub get
```

### 4. Prepare environment files (backend)
Copy `.env.example` to `.env` inside `backend` and fill in any required Firebase or API credentials.

### 5. Run the backend service
```powershell
cd ..\backend
npm start
```
By default the Node.js server listens on `http://localhost:8080`. Swagger docs are usually available at `http://localhost:8080/docs`.

### 6. Run the Flutter app
1. Ensure an Android emulator or physical device is connected.
2. From the `frontend` directory, launch the app:
   ```powershell
   cd ..\frontend
   flutter run
   ```
3. Select the desired device when prompted. The app will build and launch on the emulator or device.

## 🔍 Troubleshooting

### PowerShell ExecutionPolicy or npm.ps1 errors
If you see `npm.ps1 cannot be loaded because running scripts is disabled on this system`:
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
Restart PowerShell afterwards.

### `adb` or SDK not recognized
* Ensure `platform-tools` is added to PATH (see Environment Setup).
* Re-run `flutter doctor` to confirm the Android SDK location.
* Open Android Studio → **More Actions** → **SDK Manager** to verify the SDK path and installed packages.

### Accept Android licenses
If `flutter doctor` reports missing licenses:
```powershell
flutter doctor --android-licenses
```
Review and accept each license.

### Flutter reports missing Visual Studio components
If you plan to build Windows desktop apps, install Visual Studio with the C++ workload. Otherwise you can ignore this warning.

## 📘 Notes

* Android Studio offers powerful debugging tools and an emulator for testing the Flutter app.
* Visual Studio Code provides lightweight editing for both the Flutter frontend and Node.js backend, especially with the Flutter and Dart extensions installed.
* Keep your tools up to date—`flutter upgrade`, `npm update`, and Android Studio updates ensure compatibility.

## 🗂️ Project Structure
```
/
├── backend   # Node.js + Express REST API
└── frontend  # Flutter client application
```

* `backend/` contains the REST API, environment files, and server configuration.
* `frontend/` houses the Flutter mobile application.

Happy coding and welcome to the Ride project!
