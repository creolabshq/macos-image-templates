packer {
  required_plugins {
    tart = {
      version = ">= 1.12.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}
variable "cpu_count" {
  type = number
}

variable "memory_gb" {
  type = number
}

variable "macos_version" {
  type = string
}

variable "xcode_version" {
  type = list(string)
}

variable "additional_runtimes" {
  type    = list(string)
  default = []
}

variable "tag" {
  type    = string
  default = ""
}

variable "disk_size" {
  type    = number
  default = 100
}

variable "disk_free_mb" {
  type    = number
  default = 15000
}

variable "android_sdk_tools_version" {
  type    = string
  default = "11076708" # https://developer.android.com/studio#command-line-tools-only
}

source "tart-cli" "tart" {
  vm_base_name = "ghcr.io/cirruslabs/macos-${var.macos_version}-base:latest"
  // use tag or the last element of the xcode_version list
  vm_name      = "${var.macos_version}-xcode:${var.tag != "" ? var.tag : var.xcode_version[0]}"
  cpu_count    = var.cpu_count
  memory_gb    = var.memory_gb
  disk_size_gb = var.disk_size
  headless     = true
  ssh_password = "admin"
  ssh_username = "admin"
  ssh_timeout  = "120s"
}

locals {
  xcode_install_provisioners = [
    for version in reverse(sort(var.xcode_version)) : {
      type = "shell"
      inline = [
        "source ~/.zprofile",
        "sudo xcodes install ${version} --experimental-unxip --path /Users/admin/Downloads/Xcode_${version}.xip --select --empty-trash",
        // get selected xcode path, strip /Contents/Developer and move to GitHub compatible locations
        "INSTALLED_PATH=$(xcodes select -p)",
        "CONTENTS_DIR=$(dirname $INSTALLED_PATH)",
        "APP_DIR=$(dirname $CONTENTS_DIR)",
        "sudo mv $APP_DIR /Applications/Xcode_${version}.app",
        "sudo xcode-select -s /Applications/Xcode_${version}.app",
        "xcodebuild -downloadAllPlatforms",
        "xcodebuild -runFirstLaunch",
      ]
    }
  ]
}

build {
  sources = ["source.tart-cli.tart"]

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash",
    ]
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "nvm install --lts",
      "npm install -g pnpm",
      "pnpm -v",
      "npm install -g bun",
      "bun -v",
      "npm install -g node-gyp",
      "npm install -g eas-cli"
    ]
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew --version",
      "brew update",
      "brew upgrade",
    ]
  }

  // Re-install the GitHub Actions runner
  provisioner "shell" {
    script = "scripts/install-actions-runner.sh"
  }

  // make sure our workaround from base is still valid
  provisioner "shell" {
    inline = [
      "sudo ln -s /Users/admin /Users/runner || true"
    ]
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install openjdk@17",
      "echo 'export PATH=\"/opt/homebrew/opt/openjdk@17/bin:$PATH\"' >> ~/.zprofile",
      "echo 'export ANDROID_HOME=$HOME/android-sdk' >> ~/.zprofile",
      "echo 'export ANDROID_SDK_ROOT=$ANDROID_HOME' >> ~/.zprofile",
      "echo 'export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator' >> ~/.zprofile",
      "source ~/.zprofile",
      "wget -q https://dl.google.com/android/repository/commandlinetools-mac-${var.android_sdk_tools_version}_latest.zip -O android-sdk-tools.zip",
      "mkdir -p $ANDROID_HOME/cmdline-tools/",
      "unzip -q android-sdk-tools.zip -d $ANDROID_HOME/cmdline-tools/",
      "rm android-sdk-tools.zip",
      "mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest",
      "yes | sdkmanager --licenses",
      "yes | sdkmanager 'platform-tools' 'platforms;android-35' 'build-tools;35.0.0' 'ndk;27.2.12479018'"
    ]
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install xcodesorg/made/xcodes",
      "xcodes version",
    ]
  }

  provisioner "file" {
    sources     = [for version in var.xcode_version : pathexpand("~/XcodesCache/Xcode_${version}.xip")]
    destination = "/Users/admin/Downloads/"
  }

  // iterate over all Xcode versions and install them
  // select the latest one as the default
  dynamic "provisioner" {
    for_each = local.xcode_install_provisioners
    labels   = ["shell"]
    content {
      inline = provisioner.value.inline
    }
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "sudo xcodes select '${var.xcode_version[0]}'",
    ]
  }


  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install libimobiledevice ideviceinstaller ios-deploy fastlane carthage watchman",
      "brew install xcbeautify",
      "gem update",
      "gem install cocoapods",
      "gem install xcpretty",
      "gem uninstall --ignore-dependencies ffi && gem install ffi -- --enable-libffi-alloc"
    ]
  }

  # useful utils for mobile development
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install graphicsmagick imagemagick",
      "brew install wix/brew/applesimutils",
      "brew install gnupg"
    ]
  }

  # e2e testing
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew tap mobile-dev-inc/tap",
      "brew install maestro"
    ]
  }

  # inspired by https://github.com/actions/runner-images/blob/fb3b6fd69957772c1596848e2daaec69eabca1bb/images/macos/provision/configuration/configure-machine.sh#L33-L61
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "curl -o AppleWWDRCAG3.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer",
      "curl -o DeveloperIDG2CA.cer https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer",
      "curl -o add-certificate.swift https://raw.githubusercontent.com/actions/runner-images/fb3b6fd69957772c1596848e2daaec69eabca1bb/images/macos/provision/configuration/add-certificate.swift",
      "swiftc -suppress-warnings add-certificate.swift",
      "sudo ./add-certificate AppleWWDRCAG3.cer",
      "sudo ./add-certificate DeveloperIDG2CA.cer",
      "rm add-certificate* *.cer"
    ]
  }

  // some other health checks
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "test -d /Users/runner"
    ]
  }

  # Disable apsd[1][2] daemon as it causes high CPU usage after boot
  #
  # [1]: https://iboysoft.com/wiki/apsd-mac.html
  # [2]: https://discussions.apple.com/thread/4459153
  provisioner "shell" {
    inline = [
      "sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.apsd.plist"
    ]
  }

  # Compatibility with GitHub Actions Runner Images, where
  # /usr/local/bin belongs to the default user. Also see [2].
  #
  # [1]: https://github.com/actions/runner-images/blob/6bbddd20d76d61606bea5a0133c950cc44c370d3/images/macos/scripts/build/configure-machine.sh#L96
  # [2]: https://github.com/actions/runner-images/discussions/7607
  provisioner "shell" {
    inline = [
      "sudo chown admin /usr/local/bin"
    ]
  }

  # Wait for the "update_dyld_sim_shared_cache" process[1][2] to finish
  # to avoid wasting CPU cycles after boot
  #
  # [1]: https://apple.stackexchange.com/questions/412101/update-dyld-sim-shared-cache-is-taking-up-a-lot-of-memory
  # [2]: https://stackoverflow.com/a/68394101/9316533
  provisioner "shell" {
    inline = [
      "while pgrep -x update_dyld_sim_shared_cache >/dev/null; do echo 'Waiting for simulator cache update...'; sleep 60; done"
    ]
  }
}
