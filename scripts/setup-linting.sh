#!/bin/bash

# Setup script for SwiftLint
# This installs SwiftLint and sets up git hooks

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔧 Setting up SwiftLint for AmakaFlow iOS..."

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo -e "${YELLOW}⚠️  Homebrew is not installed.${NC}"
    echo "Please install Homebrew first: https://brew.sh"
    exit 1
fi

# Install SwiftLint
if command -v swiftlint &> /dev/null; then
    echo "✅ SwiftLint is already installed"
else
    echo "📦 Installing SwiftLint..."
    brew install swiftlint
fi

# Verify installation
if command -v swiftlint &> /dev/null; then
    echo -e "${GREEN}✅ SwiftLint installed successfully!${NC}"
    swiftlint version
else
    echo "❌ Failed to install SwiftLint"
    exit 1
fi

# Setup git pre-commit hook
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
GIT_HOOKS_DIR="$PROJECT_DIR/.git/hooks"

if [ -d "$GIT_HOOKS_DIR" ]; then
    echo "📝 Setting up git pre-commit hook..."
    cat > "$GIT_HOOKS_DIR/pre-commit" << 'EOF'
#!/bin/bash
# Pre-commit hook to run SwiftLint

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/../.." && pwd )"

cd "$PROJECT_DIR"

# Run SwiftLint
if command -v swiftlint &> /dev/null; then
    if swiftlint lint --reporter xcode; then
        exit 0
    else
        echo "❌ SwiftLint found issues. Commit aborted."
        echo "Run 'swiftlint lint' to see details, or 'swiftlint autocorrect' to fix some issues automatically."
        exit 1
    fi
else
    echo "⚠️  SwiftLint not found. Skipping lint check."
    exit 0
fi
EOF
    chmod +x "$GIT_HOOKS_DIR/pre-commit"
    echo -e "${GREEN}✅ Git pre-commit hook installed!${NC}"
else
    echo -e "${YELLOW}⚠️  .git/hooks directory not found. Skipping git hook setup.${NC}"
fi

echo ""
echo -e "${GREEN}✨ Setup complete!${NC}"
echo ""
echo "Usage:"
echo "  Run linting: ./scripts/lint.sh"
echo "  Auto-fix issues: swiftlint autocorrect"
echo "  Manual lint: swiftlint lint"

