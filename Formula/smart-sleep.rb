# frozen_string_literal: true

class SmartSleep < Formula
  desc "Intelligent clamshell mode manager for macOS"
  homepage "https://github.com/lbb00/smart-sleep"
  url "https://github.com/lbb00/smart-sleep/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "c84dc585d3111aab953cbf67a01028b922776ca342cde44615e6bdd06f0b381a"
  head "https://github.com/lbb00/smart-sleep.git", branch: "main"
  license "Unlicense"

  def install
    bin.install "smart-sleep.sh" => "smart-sleep"
  end

  def post_install
    system "#{bin}/smart-sleep", "install"
  end

  def uninstall
    system "#{bin}/smart-sleep", "uninstall"
  end

  test do
    assert_match "smart-sleep", shell_output("#{bin}/smart-sleep version")
  end
end
