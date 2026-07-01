# This cask is mirrored to the tap repo fr1j0/homebrew-claude-light at Casks/claude-light.rb.
# On each release: bump `version` and `sha256` (copy the value from the release's
# claude-light.zip.sha256 file).

cask "claude-light" do
  version "0.5.0"
  sha256 "edf3f652b9eaad70fa2495c363d372f44c7973ac223f20d524c493bfe3f50a5d"

  url "https://github.com/fr1j0/claude-light/releases/download/v#{version}/claude-light.zip"
  name "Claude Light"
  desc "Menu-bar status light for Claude Code sessions"
  homepage "https://github.com/fr1j0/claude-light"

  depends_on macos: :ventura

  app "Claude Light.app"

  caveats <<~EOS
    Launch Claude Light, then use "Install Claude Code hooks" from the menu
    to wire it into ~/.claude/settings.json.
  EOS
end
