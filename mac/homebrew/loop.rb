# Draft cask for a personal Homebrew tap. After each release:
#   1) mac/scripts/package-release.sh on a signing Mac
#   2) upload Loop-<ver>-macos.zip (+ .sha256) to GitHub Release v<ver>
#   3) replace sha256 below and bump version
cask "loop-review" do
  version "1.0.0"
  sha256 "REPLACE_AFTER_FIRST_RELEASE"

  url "https://github.com/ChrisZou/loop/releases/download/v#{version}/Loop-#{version}-macos.zip"
  name "Loop"
  desc "Human-in-the-loop Markdown review for AI agents"
  homepage "https://github.com/ChrisZou/loop"

  depends_on macos: ">= :sonoma"

  app "Loop.app"
  binary "#{appdir}/Loop.app/Contents/Resources/loop", target: "loop"

  zap trash: [
    "~/Library/Application Support/Loop",
  ]
end
