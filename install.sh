#!/usr/bin/env bash
set -e

echo "[1/5] Homebrew deps"
brew install lua switchaudio-osx nowplaying-cli pnpm
brew tap FelixKratz/formulae
brew install sketchybar

echo "[2/5] Fonts"
brew install --cask sf-symbols font-sf-mono font-sf-pro font-victor-mono-nerd-font
# App icons font (kvndrsslr) – will also install an icon map script
if [ ! -d "$HOME/sketchybar-app-font" ]; then
    git clone https://github.com/kvndrsslr/sketchybar-app-font.git "$HOME/sketchybar-app-font"
fi
cd "$HOME/sketchybar-app-font"
pnpm install
pnpm run build:install -- "$HOME/.config/sketchybar/scripts/my-script.sh" || pnpm run build:install
# If font cache is stubborn:
killall -9 fontd || true

echo "[3/5] SbarLua (framework)"
(git clone https://github.com/FelixKratz/SbarLua.git /tmp/SbarLua &&
    cd /tmp/SbarLua && make install && rm -rf /tmp/SbarLua)

echo "[4/5] Config"
mv "$HOME/.config/sketchybar" "$HOME/.config/sketchybar_backup" 2>/dev/null || true
git clone https://github.com/yourusername/sketchybar-config.git "$HOME/.config/sketchybar"

echo "[5/5] Start SketchyBar"
brew services restart sketchybar
echo "Done ✅"
