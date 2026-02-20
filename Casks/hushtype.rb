# Homebrew Cask formula for HushType
# To install locally: brew install --cask ./Casks/hushtype.rb
# To submit to homebrew-cask: https://github.com/Homebrew/homebrew-cask/blob/HEAD/CONTRIBUTING.md

cask "hushtype" do
  version "1.0.0-rc1"
  sha256 "db7a5116ffdea136bd764272d26cbdf622b6be8fb8bac9932783db0679d03f30"

  url "https://github.com/hushtype/HushType/releases/download/v#{version}/HushType-#{version}.dmg"
  name "HushType"
  desc "Privacy-first speech-to-text for macOS — runs 100% locally"
  homepage "https://github.com/hushtype/HushType"

  depends_on macos: ">= :sonoma"

  app "HushType.app"

  zap trash: [
    "~/Library/Application Support/HushType",
    "~/Library/Preferences/com.hushtype.app.plist",
    "~/Library/Caches/com.hushtype.app",
  ]
end
