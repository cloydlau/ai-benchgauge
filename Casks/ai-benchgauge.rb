cask "ai-benchgauge" do
  version "0.0.0"
  sha256 "5f53b084b401ad375be56acd98513a4f6a160d5a190aa111802baa39ae114559"
  url "https://github.com/cloydlau/ai-benchgauge/releases/download/v0.0.0/AI-BenchGauge-0.0.0-macos-universal.dmg"
  name "AI BenchGauge"
  desc "Menu-bar leaderboard and provider quota dashboard"
  homepage "https://github.com/cloydlau/ai-benchgauge"
  auto_updates true
  depends_on macos: ">= :sonoma"
  app "AI-BenchGauge.app"
end
