#!/bin/bash
# Setup script for Spoken Assistant
# Installs all dependencies for Parakeet v3 + Kokoro pipeline

echo "=========================================="
echo "Spoken Assistant - Setup"
echo "=========================================="
echo ""

# Check Python version
python_version=$(python3 --version 2>&1 | awk '{print $2}')
echo "🔍 Python version: $python_version"

# Create virtual environment
echo ""
echo "📦 Creating virtual environment..."
python3 -m venv .venv
source .venv/bin/activate

# Upgrade pip
echo "⬆️  Upgrading pip..."
pip install --upgrade pip

# Install base dependencies
echo ""
echo "📦 Installing base dependencies..."
pip install numpy sounddevice soundfile torch transformers

# Install Kokoro
echo ""
echo "📦 Installing Kokoro..."
pip install kokoro

# Install NeMo (for Parakeet)
echo ""
echo "📦 Installing NVIDIA NeMo (for Parakeet v3)..."
echo "⚠️  This may take a while..."
pip install nemo_toolkit['asr']

echo ""
echo "=========================================="
echo "✅ Setup complete!"
echo "=========================================="
echo ""
echo "To run the assistant:"
echo "  source .venv/bin/activate"
echo "  python spoken_assistant.py"
echo ""
