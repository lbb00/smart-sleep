# frozen_string_literal: true

class SmartSleep < Formula
  desc "Intelligent clamshell mode manager for macOS"
  homepage "https://github.com/lbb00/smart-sleep"
  head "https://github.com/lbb00/smart-sleep.git", branch: "main"
  license "Unlicense"

  def install
    bin.install "smart-sleep.sh" => "smart-sleep.sh"
  end

  def post_install
    system "#{bin}/smart-sleep.sh", "install"
  end

  def uninstall
    system "#{bin}/smart-sleep.sh", "uninstall"
  end

  test do
    assert_match "smart-sleep", shell_output("#{bin}/smart-sleep.sh version")
  end
end
