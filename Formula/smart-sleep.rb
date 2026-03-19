# frozen_string_literal: true

class SmartSleep < Formula
  desc "Intelligent clamshell mode manager for macOS"
  homepage "https://github.com/lbb00/smart-sleep"
  url "https://github.com/lbb00/smart-sleep/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "91ad3515d7740c6f65370583ad266f6739b5e3e161ac2b997466d7202197142c"
  head "https://github.com/lbb00/smart-sleep.git", branch: "main"
  license "Unlicense"

  def install
    bin.install "smart-sleep.sh" => "smart-sleep"
  end

  def caveats
    <<~EOS
      Finish setup by running:
        smart-sleep install

      Before removing the formula, clean up the LaunchAgent and sudoers entry:
        smart-sleep uninstall
        brew uninstall smart-sleep
    EOS
  end

  test do
    assert_match "smart-sleep", shell_output("#{bin}/smart-sleep version")
  end
end
