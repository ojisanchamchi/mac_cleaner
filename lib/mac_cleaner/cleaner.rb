require 'fileutils'

module MacCleaner
  class Cleaner
    def initialize(dry_run: false, sudo: false, interactive: false, input: $stdin)
      @dry_run = dry_run
      @sudo = sudo
      @interactive = interactive
      @input = input
      @total_size_cleaned = 0
    end

    def clean
      sections = if @interactive
                   interactive_section_selection(CLEANUP_SECTIONS)
                 else
                   CLEANUP_SECTIONS
                 end

      if sections.empty?
        puts "\nNo sections selected. Exiting."
        return
      end

      sections.each do |section|
        if section[:sudo] && !@sudo
          puts "\nSkipping '#{section[:name]}' (requires sudo)"
          next
        end
        puts "\n#{section[:name]}"
        section[:targets].each do |target|
          clean_target(target, section[:sudo])
        end
      end
      puts "\nCleanup complete. Total space freed: #{format_bytes(@total_size_cleaned)}"
    end

    private

    def clean_target(target, sudo = false)
      if target[:command]
        puts "  - #{target[:name]}"
        system(target[:command]) unless @dry_run
        return
      end

      paths = safe_glob(target[:path])
      return if paths.empty?

      deletion_candidates = []
      total_size = 0

      paths.each do |path|
        next unless File.exist?(path)

        size = get_size(path, sudo)
        next if size.zero?

        total_size += size
        deletion_candidates << path
      end

      return if total_size.zero?

      puts "  - #{target[:name]}: #{format_bytes(total_size)}"
      @total_size_cleaned += total_size

      return if @dry_run

      deletion_candidates.each do |path|
        if sudo
          system("sudo", "rm", "-rf", path)
        else
          FileUtils.rm_rf(path, verbose: false)
        end
      end
    rescue MacCleaner::TooManyOpenFilesError
      puts "  - #{target[:name]}: skipped (too many files to scan)"
    rescue Errno::EPERM, Errno::EACCES
      # Skip paths we cannot access
    end

    def interactive_section_selection(sections)
      puts "\nInteractive mode enabled. Review each section before cleaning."
      sections.each_with_object([]) do |section, selected|
        label = section[:sudo] ? "#{section[:name]} (requires sudo)" : section[:name]
        puts "\n#{label}"
        section[:targets].each do |target|
          puts "  - #{target[:name]}"
        end
        if confirm_selection?(section[:name])
          selected << section
        else
          puts "  Skipping '#{section[:name]}'"
        end
      end
    end

    def confirm_selection?(name)
      print "Proceed with '#{name}'? [y/N]: "
      $stdout.flush
      response = @input.gets
      return false unless response

      case response.strip.downcase
      when "y", "yes"
        true
      else
        false
      end
    end

    def get_size(path, sudo = false)
      return 0 unless File.exist?(path)
      return 0 unless File.readable?(path)
      command = sudo ? "sudo du -sk \"#{path}\"" : "du -sk \"#{path}\""
      begin
        `#{command}`.split.first.to_i * 1024
      rescue
        0
      end
    end

    def format_bytes(bytes)
      return "0B" if bytes.zero?
      units = ["B", "KB", "MB", "GB", "TB"]
      i = (Math.log(bytes) / Math.log(1024)).floor
      "%.2f%s" % [bytes.to_f / 1024**i, units[i]]
    end

    def safe_glob(pattern)
      expanded = File.expand_path(pattern)
      return [] unless File.exist?(expanded) || wildcard_pattern?(expanded)

      segments = expanded.split(File::SEPARATOR)

      current_paths =
        if expanded.start_with?(File::SEPARATOR)
          segments.shift
          [File::SEPARATOR]
        else
          [segments.shift || expanded]
        end

      segments.reject!(&:empty?)
      return current_paths if segments.empty? && File.exist?(expanded)

      segments.each do |segment|
        current_paths = current_paths.each_with_object([]) do |base, acc|
          next unless base
          next unless File.exist?(base)

          if wildcard_pattern?(segment)
            next unless File.directory?(base)

            begin
              Dir.each_child(base) do |entry|
                next if entry == "." || entry == ".."
                next unless File.fnmatch?(segment, entry, GLOB_FLAGS)
                acc << File.join(base, entry)
              end
            rescue Errno::EMFILE
              raise MacCleaner::TooManyOpenFilesError
            rescue Errno::ENOENT, Errno::EACCES, Errno::EPERM
              next
            end
          else
            candidate = File.join(base, segment)
            acc << candidate if File.exist?(candidate)
          end
        end

        return [] if current_paths.empty?
      end

      current_paths.map { |path| File.expand_path(path) }.uniq.sort
    end

    def wildcard_pattern?(segment)
      segment.match?(WILDCARD_PATTERN)
    end

    GLOB_FLAGS = File::FNM_EXTGLOB | File::FNM_DOTMATCH
    WILDCARD_PATTERN = /[*?\[\]{}]/.freeze
    private_constant :GLOB_FLAGS, :WILDCARD_PATTERN

    CLEANUP_SECTIONS = [
      {
        name: "Deep System Cleanup",
        sudo: true,
        targets: [
          { name: "System library caches", path: "/Library/Caches/*" },
          { name: "System library updates", path: "/Library/Updates/*" },
        ]
      },
      {
        name: "System Essentials",
        targets: [
          { name: "User app cache", path: "~/Library/Caches/*" },
          { name: "User app logs", path: "~/Library/Logs/*" },
          { name: "Trash", path: "~/.Trash/*" },
          { name: "Crash reports", path: "~/Library/Application Support/CrashReporter/*" },
          { name: "Diagnostic reports", path: "~/Library/DiagnosticReports/*" },
          { name: "QuickLook thumbnails", path: "~/Library/Caches/com.apple.QuickLook.thumbnailcache" },
        ]
      },
      {
        name: "macOS System Caches",
        targets: [
          { name: "Saved application states", path: "~/Library/Saved Application State/*" },
          { name: "Spotlight cache", path: "~/Library/Caches/com.apple.spotlight" },
          { name: "Font registry cache", path: "~/Library/Caches/com.apple.FontRegistry" },
          { name: "Font cache", path: "~/Library/Caches/com.apple.ATS" },
          { name: "Photo analysis cache", path: "~/Library/Caches/com.apple.photoanalysisd" },
          { name: "Apple ID cache", path: "~/Library/Caches/com.apple.akd" },
          { name: "Safari webpage previews", path: "~/Library/Caches/com.apple.Safari/Webpage Previews/*" },
          { name: "iCloud session cache", path: "~/Library/Application Support/CloudDocs/session/db/*" },
        ]
      },
      {
        name: "Developer Tools",
        targets: [
          { name: "npm cache directory", path: "~/.npm/_cacache/*" },
          { name: "npm logs", path: "~/.npm/_logs/*" },
          { name: "Yarn cache", path: "~/.yarn/cache/*" },
          { name: "Bun cache", path: "~/.bun/install/cache/*" },
          { name: "pip cache directory", path: "~/.cache/pip/*" },
          { name: "pip cache (macOS)", path: "~/Library/Caches/pip/*" },
          { name: "pyenv cache", path: "~/.pyenv/cache/*" },
          { name: "Go build cache", path: "~/Library/Caches/go-build/*" },
          { name: "Go module cache", path: "~/go/pkg/mod/cache/*" },
          { name: "Rust cargo cache", path: "~/.cargo/registry/cache/*" },
          { name: "Kubernetes cache", path: "~/.kube/cache/*" },
          { name: "Container storage temp", path: "~/.local/share/containers/storage/tmp/*" },
          { name: "AWS CLI cache", path: "~/.aws/cli/cache/*" },
          { name: "Google Cloud logs", path: "~/.config/gcloud/logs/*" },
          { name: "Azure CLI logs", path: "~/.azure/logs/*" },
          { name: "Homebrew cache", path: "~/Library/Caches/Homebrew/*" },
          { name: "Homebrew lock files (M series)", path: "/opt/homebrew/var/homebrew/locks/*" },
          { name: "Homebrew lock files (Intel)", path: "/usr/local/var/homebrew/locks/*" },
          { name: "Git config lock", path: "~/.gitconfig.lock" },
        ]
      },
      {
        name: "Tool Caches",
        targets: [
          { name: "npm cache", command: "npm cache clean --force" },
          { name: "pip cache", command: "pip cache purge" },
          { name: "Go cache", command: "go clean -modcache" },
          { name: "Homebrew cleanup", command: "brew cleanup -s" },
        ]
      },
      {
        name: "Sandboxed App Caches",
        targets: [
          { name: "Wallpaper agent cache", path: "~/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/*" },
          { name: "Media analysis cache", path: "~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches/*" },
          { name: "App Store cache", path: "~/Library/Containers/com.apple.AppStore/Data/Library/Caches/*" },
          { name: "Sandboxed app caches", path: "~/Library/Containers/*/Data/Library/Caches/*" },
        ]
      },
      {
        name: "Browser Cleanup",
        targets: [
          { name: "Safari cache", path: "~/Library/Caches/com.apple.Safari/*" },
          { name: "Chrome cache", path: "~/Library/Caches/Google/Chrome/*" },
          { name: "Chrome app cache", path: "~/Library/Application Support/Google/Chrome/*/Application Cache/*" },
          { name: "Chrome GPU cache", path: "~/Library/Application Support/Google/Chrome/*/GPUCache/*" },
          { name: "Chromium cache", path: "~/Library/Caches/Chromium/*" },
          { name: "Edge cache", path: "~/Library/Caches/com.microsoft.edgemac/*" },
          { name: "Arc cache", path: "~/Library/Caches/company.thebrowser.Browser/*" },
          { name: "Brave cache", path: "~/Library/Caches/BraveSoftware/Brave-Browser/*" },
          { name: "Firefox cache", path: "~/Library/Caches/Firefox/*" },
          { name: "Opera cache", path: "~/Library/Caches/com.operasoftware.Opera/*" },
          { name: "Vivaldi cache", path: "~/Library/Caches/com.vivaldi.Vivaldi/*" },
          { name: "Firefox profile cache", path: "~/Library/Application Support/Firefox/Profiles/*/cache2/*" },
        ]
      },
      {
        name: "Cloud Storage Caches",
        targets: [
          { name: "Dropbox cache", path: "~/Library/Caches/com.dropbox.*" },
          { name: "Dropbox cache", path: "~/Library/Caches/com.getdropbox.dropbox" },
          { name: "Google Drive cache", path: "~/Library/Caches/com.google.GoogleDrive" },
          { name: "Baidu Netdisk cache", path: "~/Library/Caches/com.baidu.netdisk" },
          { name: "Alibaba Cloud cache", path: "~/Library/Caches/com.alibaba.teambitiondisk" },
          { name: "Box cache", path: "~/Library/Caches/com.box.desktop" },
          { name: "OneDrive cache", path: "~/Library/Caches/com.microsoft.OneDrive" },
        ]
      },
      {
        name: "Office Applications",
        targets: [
          { name: "Microsoft Word cache", path: "~/Library/Caches/com.microsoft.Word" },
          { name: "Microsoft Excel cache", path: "~/Library/Caches/com.microsoft.Excel" },
          { name: "Microsoft PowerPoint cache", path: "~/Library/Caches/com.microsoft.Powerpoint" },
          { name: "Microsoft Outlook cache", path: "~/Library/Caches/com.microsoft.Outlook/*" },
          { name: "Apple iWork cache", path: "~/Library/Caches/com.apple.iWork.*" },
          { name: "WPS Office cache", path: "~/Library/Caches/com.kingsoft.wpsoffice.mac" },
          { name: "Thunderbird cache", path: "~/Library/Caches/org.mozilla.thunderbird/*" },
          { name: "Apple Mail cache", path: "~/Library/Caches/com.apple.mail/*" },
        ]
      },
      {
        name: "Extended Developer Caches",
        targets: [
          { name: "pnpm store cache", path: "~/.pnpm-store/*" },
          { name: "pnpm global store", path: "~/.local/share/pnpm/store/*" },
          { name: "TypeScript cache", path: "~/.cache/typescript/*" },
          { name: "Electron cache", path: "~/.cache/electron/*" },
          { name: "node-gyp cache", path: "~/.cache/node-gyp/*" },
          { name: "node-gyp build cache", path: "~/.node-gyp/*" },
          { name: "Turbo cache", path: "~/.turbo/*" },
          { name: "Next.js cache", path: "~/.next/*" },
          { name: "Vite cache", path: "~/.vite/*" },
          { name: "Vite global cache", path: "~/.cache/vite/*" },
          { name: "Webpack cache", path: "~/.cache/webpack/*" },
          { name: "Parcel cache", path: "~/.parcel-cache/*" },
          { name: "Android Studio cache", path: "~/Library/Caches/Google/AndroidStudio*/*" },
          { name: "Unity cache", path: "~/Library/Caches/com.unity3d.*/*" },
          { name: "JetBrains Toolbox cache", path: "~/Library/Caches/com.jetbrains.toolbox/*" },
          { name: "Postman cache", path: "~/Library/Caches/com.postmanlabs.mac/*" },
          { name: "Insomnia cache", path: "~/Library/Caches/com.konghq.insomnia/*" },
          { name: "TablePlus cache", path: "~/Library/Caches/com.tinyapp.TablePlus/*" },
          { name: "MongoDB Compass cache", path: "~/Library/Caches/com.mongodb.compass/*" },
          { name: "Figma cache", path: "~/Library/Caches/com.figma.Desktop/*" },
          { name: "GitHub Desktop cache", path: "~/Library/Caches/com.github.GitHubDesktop/*" },
          { name: "VS Code cache", path: "~/Library/Caches/com.microsoft.VSCode/*" },
          { name: "Sublime Text cache", path: "~/Library/Caches/com.sublimetext.*/*" },
          { name: "Poetry cache", path: "~/.cache/poetry/*" },
          { name: "uv cache", path: "~/.cache/uv/*" },
          { name: "Ruff cache", path: "~/.cache/ruff/*" },
          { name: "MyPy cache", path: "~/.cache/mypy/*" },
          { name: "Pytest cache", path: "~/.pytest_cache/*" },
          { name: "Jupyter runtime cache", path: "~/.jupyter/runtime/*" },
          { name: "Hugging Face cache", path: "~/.cache/huggingface/*" },
          { name: "PyTorch cache", path: "~/.cache/torch/*" },
          { name: "TensorFlow cache", path: "~/.cache/tensorflow/*" },
          { name: "Conda packages cache", path: "~/.conda/pkgs/*" },
          { name: "Anaconda packages cache", path: "~/anaconda3/pkgs/*" },
          { name: "Weights & Biases cache", path: "~/.cache/wandb/*" },
          { name: "Cargo git cache", path: "~/.cargo/git/*" },
          { name: "Rust documentation cache", path: "~/.rustup/toolchains/*/share/doc/*" },
          { name: "Rust downloads cache", path: "~/.rustup/downloads/*" },
          { name: "Gradle caches", path: "~/.gradle/caches/*" },
          { name: "Maven repository cache", path: "~/.m2/repository/*" },
          { name: "SBT cache", path: "~/.sbt/*" },
          { name: "Docker BuildX cache", path: "~/.docker/buildx/cache/*" },
          { name: "Terraform cache", path: "~/.cache/terraform/*" },
          { name: "Paw API cache", path: "~/Library/Caches/com.getpaw.Paw/*" },
          { name: "Charles Proxy cache", path: "~/Library/Caches/com.charlesproxy.charles/*" },
          { name: "Proxyman cache", path: "~/Library/Caches/com.proxyman.NSProxy/*" },
          { name: "Grafana cache", path: "~/.grafana/cache/*" },
          { name: "Prometheus WAL cache", path: "~/.prometheus/data/wal/*" },
          { name: "Jenkins workspace cache", path: "~/.jenkins/workspace/*/target/*" },
          { name: "GitLab Runner cache", path: "~/.cache/gitlab-runner/*" },
          { name: "GitHub Actions cache", path: "~/.github/cache/*" },
          { name: "CircleCI cache", path: "~/.circleci/cache/*" },
          { name: "Oh My Zsh cache", path: "~/.oh-my-zsh/cache/*" },
          { name: "Fish shell backup", path: "~/.config/fish/fish_history.bak*" },
          { name: "Bash history backup", path: "~/.bash_history.bak*" },
          { name: "Zsh history backup", path: "~/.zsh_history.bak*" },
          { name: "SonarQube cache", path: "~/.sonar/*" },
          { name: "ESLint cache", path: "~/.cache/eslint/*" },
          { name: "Prettier cache", path: "~/.cache/prettier/*" },
          { name: "CocoaPods cache", path: "~/Library/Caches/CocoaPods/*" },
          { name: "Ruby Bundler cache", path: "~/.bundle/cache/*" },
          { name: "PHP Composer cache", path: "~/.composer/cache/*" },
          { name: "NuGet packages cache", path: "~/.nuget/packages/*" },
          { name: "Ivy cache", path: "~/.ivy2/cache/*" },
          { name: "Dart Pub cache", path: "~/.pub-cache/*" },
          { name: "curl cache", path: "~/.cache/curl/*" },
          { name: "wget cache", path: "~/.cache/wget/*" },
          { name: "curl cache (macOS)", path: "~/Library/Caches/curl/*" },
          { name: "wget cache (macOS)", path: "~/Library/Caches/wget/*" },
          { name: "pre-commit cache", path: "~/.cache/pre-commit/*" },
          { name: "Git config backup", path: "~/.gitconfig.bak*" },
          { name: "Flutter cache", path: "~/.cache/flutter/*" },
          { name: "Gradle daemon logs", path: "~/.gradle/daemon/*" },
          { name: "Android build cache", path: "~/.android/build-cache/*" },
          { name: "Android SDK cache", path: "~/.android/cache/*" },
          { name: "iOS device cache", path: "~/Library/Developer/Xcode/iOS DeviceSupport/*/Symbols/System/Library/Caches/*" },
          { name: "Xcode Interface Builder cache", path: "~/Library/Developer/Xcode/UserData/IB Support/*" },
          { name: "Swift package manager cache", path: "~/.cache/swift-package-manager/*" },
          { name: "Bazel cache", path: "~/.cache/bazel/*" },
          { name: "Zig cache", path: "~/.cache/zig/*" },
          { name: "Deno cache", path: "~/Library/Caches/deno/*" },
          { name: "Sequel Ace cache", path: "~/Library/Caches/com.sequel-ace.sequel-ace/*" },
          { name: "Sequel Pro cache", path: "~/Library/Caches/com.eggerapps.Sequel-Pro/*" },
          { name: "Redis Desktop Manager cache", path: "~/Library/Caches/redis-desktop-manager/*" },
          { name: "Navicat cache", path: "~/Library/Caches/com.navicat.*" },
          { name: "DBeaver cache", path: "~/Library/Caches/com.dbeaver.*" },
          { name: "Redis Insight cache", path: "~/Library/Caches/com.redis.RedisInsight" },
          { name: "Sentry crash reports", path: "~/Library/Caches/SentryCrash/*" },
          { name: "KSCrash reports", path: "~/Library/Caches/KSCrash/*" },
          { name: "Crashlytics data", path: "~/Library/Caches/com.crashlytics.data/*" },
        ]
      },
      {
        name: "Applications",
        targets: [
          { name: "Xcode derived data", path: "~/Library/Developer/Xcode/DerivedData/*" },
          { name: "Simulator cache", path: "~/Library/Developer/CoreSimulator/Caches/*" },
          { name: "Simulator temp files", path: "~/Library/Developer/CoreSimulator/Devices/*/data/tmp/*" },
          { name: "Xcode cache", path: "~/Library/Caches/com.apple.dt.Xcode/*" },
          { name: "iOS device logs", path: "~/Library/Developer/Xcode/iOS Device Logs/*" },
          { name: "watchOS device logs", path: "~/Library/Developer/Xcode/watchOS Device Logs/*" },
          { name: "Xcode build products", path: "~/Library/Developer/Xcode/Products/*" },
          { name: "VS Code logs", path: "~/Library/Application Support/Code/logs/*" },
          { name: "VS Code cache", path: "~/Library/Application Support/Code/Cache/*" },
          { name: "VS Code extension cache", path: "~/Library/Application Support/Code/CachedExtensions/*" },
          { name: "VS Code data cache", path: "~/Library/Application Support/Code/CachedData/*" },
          { name: "IntelliJ IDEA logs", path: "~/Library/Logs/IntelliJIdea*/*" },
          { name: "PhpStorm logs", path: "~/Library/Logs/PhpStorm*/*" },
          { name: "PyCharm logs", path: "~/Library/Logs/PyCharm*/*" },
          { name: "WebStorm logs", path: "~/Library/Logs/WebStorm*/*" },
          { name: "GoLand logs", path: "~/Library/Logs/GoLand*/*" },
          { name: "CLion logs", path: "~/Library/Logs/CLion*/*" },
          { name: "DataGrip logs", path: "~/Library/Logs/DataGrip*/*" },
          { name: "JetBrains cache", path: "~/Library/Caches/JetBrains/*" },
          { name: "Discord cache", path: "~/Library/Application Support/discord/Cache/*" },
          { name: "Slack cache", path: "~/Library/Application Support/Slack/Cache/*" },
          { name: "Zoom cache", path: "~/Library/Caches/us.zoom.xos/*" },
          { name: "WeChat cache", path: "~/Library/Caches/com.tencent.xinWeChat/*" },
          { name: "Telegram cache", path: "~/Library/Caches/ru.keepcoder.Telegram/*" },
          { name: "ChatGPT cache", path: "~/Library/Caches/com.openai.chat/*" },
          { name: "Claude desktop cache", path: "~/Library/Caches/com.anthropic.claudefordesktop/*" },
          { name: "Claude logs", path: "~/Library/Logs/Claude/*" },
          { name: "Microsoft Teams cache", path: "~/Library/Caches/com.microsoft.teams2/*" },
          { name: "WhatsApp cache", path: "~/Library/Caches/net.whatsapp.WhatsApp/*" },
          { name: "Skype cache", path: "~/Library/Caches/com.skype.skype/*" },
          { name: "DingTalk (iDingTalk) cache", path: "~/Library/Caches/dd.work.exclusive4aliding/*" },
          { name: "AliLang security component", path: "~/Library/Caches/com.alibaba.AliLang.osx/*" },
          { name: "DingTalk logs", path: "~/Library/Application Support/iDingTalk/log/*" },
          { name: "DingTalk holmes logs", path: "~/Library/Application Support/iDingTalk/holmeslogs/*" },
          { name: "Tencent Meeting cache", path: "~/Library/Caches/com.tencent.meeting/*" },
          { name: "WeCom cache", path: "~/Library/Caches/com.tencent.WeWorkMac/*" },
          { name: "Feishu cache", path: "~/Library/Caches/com.feishu.*/*" },
          { name: "Sketch cache", path: "~/Library/Caches/com.bohemiancoding.sketch3/*" },
          { name: "Sketch app cache", path: "~/Library/Application Support/com.bohemiancoding.sketch3/cache/*" },
          { name: "ScreenFlow cache", path: "~/Library/Caches/net.telestream.screenflow10/*" },
          { name: "Adobe cache", path: "~/Library/Caches/Adobe/*" },
          { name: "Adobe app caches", path: "~/Library/Caches/com.adobe.*/*" },
          { name: "Adobe media cache", path: "~/Library/Application Support/Adobe/Common/Media Cache Files/*" },
          { name: "Adobe peak files", path: "~/Library/Application Support/Adobe/Common/Peak Files/*" },
          { name: "Final Cut Pro cache", path: "~/Library/Caches/com.apple.FinalCut/*" },
          { name: "Final Cut render cache", path: "~/Library/Application Support/Final Cut Pro/*/Render Files/*" },
          { name: "Motion render cache", path: "~/Library/Application Support/Motion/*/Render Files/*" },
          { name: "DaVinci Resolve cache", path: "~/Library/Caches/com.blackmagic-design.DaVinciResolve/*" },
          { name: "Premiere Pro cache", path: "~/Library/Caches/com.adobe.PremierePro.*/*" },
          { name: "Blender cache", path: "~/Library/Caches/org.blenderfoundation.blender/*" },
          { name: "Cinema 4D cache", path: "~/Library/Caches/com.maxon.cinema4d/*" },
          { name: "Autodesk cache", path: "~/Library/Caches/com.autodesk.*/*" },
          { name: "SketchUp cache", path: "~/Library/Caches/com.sketchup.*/*" },
          { name: "Raycast cache", path: "~/Library/Caches/com.raycast.macos/*" },
          { name: "MiaoYan cache", path: "~/Library/Caches/com.tw93.MiaoYan/*" },
          { name: "Filo cache", path: "~/Library/Caches/com.filo.client/*" },
          { name: "Flomo cache", path: "~/Library/Caches/com.flomoapp.mac/*" },
          { name: "Spotify cache", path: "~/Library/Caches/com.spotify.client/*" },
          { name: "Apple Music cache", path: "~/Library/Caches/com.apple.Music" },
          { name: "Apple Podcasts cache", path: "~/Library/Caches/com.apple.podcasts" },
          { name: "Apple TV cache", path: "~/Library/Caches/com.apple.TV/*" },
          { name: "Plex cache", path: "~/Library/Caches/tv.plex.player.desktop" },
          { name: "NetEase Music cache", path: "~/Library/Caches/com.netease.163music" },
          { name: "QQ Music cache", path: "~/Library/Caches/com.tencent.QQMusic/*" },
          { name: "Kugou Music cache", path: "~/Library/Caches/com.kugou.mac/*" },
          { name: "Kuwo Music cache", path: "~/Library/Caches/com.kuwo.mac/*" },
          { name: "IINA cache", path: "~/Library/Caches/com.colliderli.iina" },
          { name: "VLC cache", path: "~/Library/Caches/org.videolan.vlc" },
          { name: "MPV cache", path: "~/Library/Caches/io.mpv" },
          { name: "iQIYI cache", path: "~/Library/Caches/com.iqiyi.player" },
          { name: "Tencent Video cache", path: "~/Library/Caches/com.tencent.tenvideo" },
          { name: "Bilibili cache", path: "~/Library/Caches/tv.danmaku.bili/*" },
          { name: "Douyu cache", path: "~/Library/Caches/com.douyu.*/*" },
          { name: "Huya cache", path: "~/Library/Caches/com.huya.*/*" },
          { name: "Aria2 cache", path: "~/Library/Caches/net.xmac.aria2gui" },
          { name: "Transmission cache", path: "~/Library/Caches/org.m0k.transmission" },
          { name: "qBittorrent cache", path: "~/Library/Caches/com.qbittorrent.qBittorrent" },
          { name: "Downie cache", path: "~/Library/Caches/com.downie.Downie-*" },
          { name: "Folx cache", path: "~/Library/Caches/com.folx.*/*" },
          { name: "Pacifist cache", path: "~/Library/Caches/com.charlessoft.pacifist/*" },
          { name: "Steam cache", path: "~/Library/Caches/com.valvesoftware.steam/*" },
          { name: "Steam app cache", path: "~/Library/Application Support/Steam/appcache/*" },
          { name: "Steam web cache", path: "~/Library/Application Support/Steam/htmlcache/*" },
          { name: "Epic Games cache", path: "~/Library/Caches/com.epicgames.EpicGamesLauncher/*" },
          { name: "Battle.net cache", path: "~/Library/Caches/com.blizzard.Battle.net/*" },
          { name: "Battle.net app cache", path: "~/Library/Application Support/Battle.net/Cache/*" },
          { name: "EA Origin cache", path: "~/Library/Caches/com.ea.*/*" },
          { name: "GOG Galaxy cache", path: "~/Library/Caches/com.gog.galaxy/*" },
          { name: "Riot Games cache", path: "~/Library/Caches/com.riotgames.*/*" },
          { name: "Youdao Dictionary cache", path: "~/Library/Caches/com.youdao.YoudaoDict" },
          { name: "Eudict cache", path: "~/Library/Caches/com.eudic.*" },
          { name: "Bob Translation cache", path: "~/Library/Caches/com.bob-build.Bob" },
          { name: "CleanShot cache", path: "~/Library/Caches/com.cleanshot.*" },
          { name: "Camo cache", path: "~/Library/Caches/com.reincubate.camo" },
          { name: "Xnip cache", path: "~/Library/Caches/com.xnipapp.xnip" },
          { name: "Spark cache", path: "~/Library/Caches/com.readdle.smartemail-Mac" },
          { name: "Airmail cache", path: "~/Library/Caches/com.airmail.*" },
          { name: "Todoist cache", path: "~/Library/Caches/com.todoist.mac.Todoist" },
          { name: "Any.do cache", path: "~/Library/Caches/com.any.do.*" },
          { name: "Zsh completion cache", path: "~/.zcompdump*" },
          { name: "less history", path: "~/.lesshst" },
          { name: "Vim temporary files", path: "~/.viminfo.tmp" },
          { name: "wget HSTS cache", path: "~/.wget-hsts" },
          { name: "Input Source Pro cache", path: "~/Library/Caches/com.runjuu.Input-Source-Pro/*" },
          { name: "WakaTime cache", path: "~/Library/Caches/macos-wakatime.WakaTime/*" },
          { name: "Notion cache", path: "~/Library/Caches/notion.id/*" },
          { name: "Obsidian cache", path: "~/Library/Caches/md.obsidian/*" },
          { name: "Logseq cache", path: "~/Library/Caches/com.logseq.*/*" },
          { name: "Bear cache", path: "~/Library/Caches/com.bear-writer.*/*" },
          { name: "Evernote cache", path: "~/Library/Caches/com.evernote.*/*" },
          { name: "Yinxiang Note cache", path: "~/Library/Caches/com.yinxiang.*/*" },
          { name: "Alfred cache", path: "~/Library/Caches/com.runningwithcrayons.Alfred/*" },
          { name: "The Unarchiver cache", path: "~/Library/Caches/cx.c3.theunarchiver/*" },
          { name: "TeamViewer cache", path: "~/Library/Caches/com.teamviewer.*/*" },
          { name: "AnyDesk cache", path: "~/Library/Caches/com.anydesk.*/*" },
          { name: "ToDesk cache", path: "~/Library/Caches/com.todesk.*/*" },
          { name: "Sunlogin cache", path: "~/Library/Caches/com.sunlogin.*/*" },
        ]
      },
      {
        name: "Virtualization Tools",
        targets: [
          { name: "VMware Fusion cache", path: "~/Library/Caches/com.vmware.fusion" },
          { name: "Parallels cache", path: "~/Library/Caches/com.parallels.*" },
          { name: "VirtualBox cache", path: "~/VirtualBox VMs/.cache" },
          { name: "Vagrant temporary files", path: "~/.vagrant.d/tmp/*" },
        ]
      },
      {
        name: "Application Support Logs",
        targets: [
          { name: "App logs", path: "~/Library/Application Support/*/log/*" },
          { name: "App logs", path: "~/Library/Application Support/*/logs/*" },
          { name: "Activity logs", path: "~/Library/Application Support/*/activitylog/*" },
        ]
      }
    ]
  end
end
