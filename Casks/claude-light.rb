# This cask is mirrored to the tap repo fr1j0/homebrew-claude-light at Casks/claude-light.rb.
# On each release: bump `version` and `sha256` (copy the value from the release's
# claude-light.zip.sha256 file).

cask "claude-light" do
  version "0.4.0"
  sha256 "c07a5ce42cee74f020691593dd7c5ff808050ce6296b0ee01a3f227c42c4c4d1"

  url "https://github.com/fr1j0/claude-light/releases/download/v#{version}/claude-light.zip"
  name "Claude Light"
  desc "Menu-bar status light for Claude Code sessions"
  homepage "https://github.com/fr1j0/claude-light"

  app "Claude Light.app"

  caveats <<~EOS
    Launch Claude Light, then use "Install Claude Code hooks" from the menu
    to wire it into ~/.claude/settings.json.
  EOS
end
