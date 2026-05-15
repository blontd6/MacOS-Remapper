## Installation & Build

### Prerequisites

- macOS (Intel or Apple Silicon)
- Xcode Command Line Tools
  - Run the following if you don't already have the Xcode Command Line Tools:

  ```bash
  xcode-select --install
  ```


### Building the Project
In your terminal:
1. Clone the repository and navigate to the project directory:
   ```bash
   git clone https://github.com/blontd6/MacOS-Remapper.git
   cd MacOS-Remapper
   ```

2. Run the build script:
   ```bash
   sh build.sh
   ```
   This will compile the `KeyRemapper.m` file into a native executable named `KeyRemapper`.

## Usage

### Running the App

Start the utility from your terminal:
```bash
./KeyRemapper
```

### Granting Permissions

Because this tool intercepts keyboard events, macOS requires **Accessibility Permissions**:

1. When you first run the app, you may see an error or a prompt.
2. Go to **System Settings > Privacy & Security > Accessibility**.
3. Add or toggle on your **Terminal** (Terminal.app or your IDE/Different Terminal).
4. Restart the `KeyRemapper`.

### Navigating the UI

- **Arrow Keys (Up/Down)**: Navigate the menu options.
- **Enter/Return**: Select an option.
- **Add/Edit Keybind**: 
  - Select this option.
  - Press the **Origin Key** (the key you want to change).
  - Press the **Target Key** (the key you want it to act as).
- **Delete Keybind**:
  - Select this option.
  - Press the **Origin Key** of the mapping you want to remove.
- **Quit**: Exit the application (or press `q` or `Ctrl+C`).

