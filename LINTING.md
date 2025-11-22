# SwiftLint Setup Guide

This project uses [SwiftLint](https://github.com/realm/SwiftLint) to enforce code style and catch common errors before they cause build failures.

## Quick Setup

Run the setup script to install SwiftLint and configure git hooks:

```bash
./scripts/setup-linting.sh
```

This will:
- Install SwiftLint via Homebrew
- Set up a git pre-commit hook to run linting automatically
- Verify the installation

## Manual Installation

If you prefer to install manually:

```bash
brew install swiftlint
```

## Usage

### Run Linting

Check all files for issues:

```bash
./scripts/lint.sh
```

Or use SwiftLint directly:

```bash
swiftlint lint
```

### Auto-Fix Issues

SwiftLint can automatically fix many issues:

```bash
swiftlint autocorrect
```

### Before Committing

The git pre-commit hook will automatically run SwiftLint before each commit. If issues are found, the commit will be blocked until they're fixed.

To bypass the hook (not recommended):

```bash
git commit --no-verify
```

## Configuration

The SwiftLint configuration is in `.swiftlint.yml` at the root of the project. Key settings:

- **Line length**: 120 characters (warning), 200 (error)
- **File length**: 500 lines (warning), 1000 (error)
- **Reporter**: Xcode format for integration with Xcode

## Common Issues

### "SwiftLint not found"

Make sure SwiftLint is installed:
```bash
brew install swiftlint
```

### "Command not found: swiftlint"

Add SwiftLint to your PATH, or use the full path:
```bash
/opt/homebrew/bin/swiftlint lint
```

### Disable a Rule for Specific Code

If you need to disable a rule for a specific line:

```swift
// swiftlint:disable:next line_length
let veryLongLine = "This is a very long line that exceeds the limit"
```

Or for a block:

```swift
// swiftlint:disable line_length
let line1 = "very long"
let line2 = "also very long"
// swiftlint:enable line_length
```

## Integration with Xcode

SwiftLint can be integrated directly into Xcode:

1. Open your Xcode project
2. Go to Build Phases
3. Click "+" and select "New Run Script Phase"
4. Add this script:

```bash
if which swiftlint >/dev/null; then
  swiftlint
else
  echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
fi
```

This will run SwiftLint as part of the build process and show warnings/errors in Xcode.

## CI/CD Integration

For CI/CD pipelines, add this step:

```yaml
- name: Run SwiftLint
  run: |
    brew install swiftlint
    swiftlint lint
```

## Resources

- [SwiftLint Documentation](https://github.com/realm/SwiftLint)
- [SwiftLint Rules](https://realm.github.io/SwiftLint/rule-directory.html)
- [Configuration Options](https://github.com/realm/SwiftLint#configuration)

