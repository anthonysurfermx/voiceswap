#!/bin/bash

# VoiceSwap Installation Script
# Sets up the development environment for iOS

set -e

echo "🚀 VoiceSwap Installation Script"
echo "================================"
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
  echo "❌ This script requires macOS for iOS development"
  exit 1
fi

# Check Node.js
if ! command -v node &> /dev/null; then
  echo "❌ Node.js is not installed. Please install Node.js 20+ first."
  echo "   Visit: https://nodejs.org"
  exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 20 ]; then
  echo "⚠️  Node.js version is $NODE_VERSION. Recommended: 20+"
fi

echo "✅ Node.js $(node -v) detected"

# Check for Xcode
if ! command -v xcodebuild &> /dev/null; then
  echo "❌ Xcode is not installed. Install from App Store."
  exit 1
fi

echo "✅ Xcode detected"

# Check for CocoaPods
if ! command -v pod &> /dev/null; then
  echo "⚠️  CocoaPods not found. Installing..."
  sudo gem install cocoapods
fi

echo "✅ CocoaPods detected"

# Install npm dependencies
echo ""
echo "📦 Installing dependencies..."
npm install

# Check for .env file
if [ ! -f ".env" ]; then
  echo ""
  echo "⚠️  .env file not found. Creating from example..."
  cp .env.example .env
  echo "✅ Created .env file"
  echo ""
  echo "⚠️  IMPORTANT: Edit .env and add your API keys:"
  echo "   - EXPO_PUBLIC_THIRDWEB_CLIENT_ID (you have this)"
  echo "   - THIRDWEB_SECRET_KEY (you have this)"
  echo "   - EXPO_PUBLIC_OPENAI_API_KEY (get from openai.com)"
  echo ""
fi

# Setup info
echo ""
echo "✅ Installation complete!"
echo ""
echo "📋 Next Steps:"
echo ""
echo "1. Configure environment variables:"
echo "   Edit mobile-app/.env and add:"
echo "   - OpenAI API key"
echo "   - Backend URL (after deploy)"
echo ""
echo "2. Start development server:"
echo "   npm run ios"
echo ""
echo "3. For production build:"
echo "   eas build --platform ios"
echo ""
echo "📚 Documentation:"
echo "   - Setup guide: ./SETUP.md"
echo "   - Native module: ./IOS_NATIVE_MODULE.md"
echo ""
echo "💬 Need help? Ask in x402 Hackathon Discord"
echo ""
