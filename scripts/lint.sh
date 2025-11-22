#!/bin/bash

# SwiftLint script for AmakaFlow iOS
# This script runs SwiftLint to check code quality before committing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "🔍 Running SwiftLint..."

# Check if SwiftLint is installed
if ! command -v swiftlint &> /dev/null; then
    echo -e "${YELLOW}⚠️  SwiftLint is not installed.${NC}"
    echo "Install it with: brew install swiftlint"
    echo "Or visit: https://github.com/realm/SwiftLint"
    exit 1
fi

# Change to project directory
cd "$PROJECT_DIR"

# Run SwiftLint
if swiftlint lint --reporter xcode; then
    echo -e "${GREEN}✅ SwiftLint passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ SwiftLint found issues. Please fix them before committing.${NC}"
    exit 1
fi

