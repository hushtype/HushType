# Homebrew Cask formula for VaulType
# To install locally: brew install --cask ./Casks/vaultype.rb
# To submit to homebrew-cask: https://github.com/Homebrew/homebrew-cask/blob/HEAD/CONTRIBUTING.md

cask "vaultype" do
  version "1.0.0-rc1"
  sha256 "db7a5116ffdea136bd764272d26cbdf622b6be8fb8bac9932783db0679d03f30"

  url "https://github.com/vaultype/VaulType/releases/download/v#{version}/VaulType-#{version}.dmg"
  name "VaulType"
  desc "Privacy-first speech-to-text for macOS — runs 100% locally"
  homepage "https://github.com/vaultype/VaulType"

  depends_on macos: ">= :sonoma"

  app "VaulType.app"

  zap trash: [
    "~/Library/Application Support/VaulType",
    "~/Library/Preferences/com.vaultype.app.plist",
    "~/Library/Caches/com.vaultype.app",
  ]
end
