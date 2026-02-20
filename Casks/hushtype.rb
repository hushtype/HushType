# Homebrew Cask formula for HushType
# To install locally: brew install --cask ./Casks/hushtype.rb
# To submit to homebrew-cask: https://github.com/Homebrew/homebrew-cask/blob/HEAD/CONTRIBUTING.md

cask "hushtype" do
  version "1.0.0"
  sha256 "PLACEHOLDER_SHA256"

  url "https://github.com/harungungorer/HushType/releases/download/v#{version}/HushType-#{version}.dmg"
  name "HushType"
  desc "Privacy-first speech-to-text for macOS — runs 100% locally"
  homepage "https://github.com/harungungorer/HushType"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "HushType.app"

  zap trash: [
    "~/Library/Application Support/HushType",
    "~/Library/Preferences/com.hushtype.app.plist",
    "~/Library/Caches/com.hushtype.app",
  ]
end
