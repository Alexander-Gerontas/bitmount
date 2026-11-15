class Bitmount < Formula
  desc "Open BitLocker-encrypted drives on macOS, read-write"
  homepage "https://github.com/Alexander-Gerontas/bitmount"
  url "https://github.com/Alexander-Gerontas/bitmount/releases/download/v0.1.0/BitMount-0.1.0.zip"
  sha256 "7121cf06b374d49cfd2c86289905048c9c8d048976841658755a3f9f2cb79d2d"
  license "MIT"

  depends_on arch: :arm64
  depends_on macos: :sequoia
  depends_on "nohajc/anylinuxfs/anylinuxfs"

  def install
    # The zip holds only BitMount.app, so Homebrew unpacks straight into the bundle.
    (prefix/"BitMount.app").install "Contents"

    (bin/"bitmount").write <<~SH
      #!/bin/bash
      exec /usr/bin/open "#{opt_prefix}/BitMount.app" "$@"
    SH
  end

  def caveats
    <<~EOS
      Start BitMount with:
        bitmount

      If you have not set up anylinuxfs yet, run once:
        anylinuxfs init
    EOS
  end

  test do
    app = prefix/"BitMount.app"
    system "/usr/bin/codesign", "--verify", "--deep", "--strict", app
    plist = app/"Contents/Info.plist"
    assert_equal version.to_s,
                 shell_output("/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' #{plist}").strip
  end
end
