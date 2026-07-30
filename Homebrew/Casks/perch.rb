cask "perch" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/Arunava-K/Perch/releases/download/v#{version}/Perch.dmg"
  name "Perch"
  desc "Notch clipboard manager and live activities for macOS"
  homepage "https://github.com/Arunava-K/Perch"

  depends_on macos: ">= :sequoia"

  app "Perch.app"

  zap trash: [
    "~/Library/Application Support/Perch",
    "~/Library/Preferences/com.arunavak.perch.plist",
  ]

  caveats <<~EOS
    Perch is currently distributed unsigned. After install, clear quarantine once:

      xattr -dr com.apple.quarantine /Applications/Perch.app
  EOS
end
