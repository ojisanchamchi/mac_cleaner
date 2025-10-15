require 'open3'
require 'fileutils'
require 'digest'

module MacCleaner
  class Analyzer
    MIN_LARGE_FILE_SIZE = 1_000_000_000 # 1GB
    MIN_MEDIUM_FILE_SIZE = 100_000_000 # 100MB
    CACHE_DIR = File.expand_path("~/.cache/mac_cleaner")

    def initialize(path: "~")
      @path = File.expand_path(path)
      @path_hash = Digest::MD5.hexdigest(@path)
      @large_files = []
      @medium_files = []
      @directories = []
      @aggregated_directories = []
      FileUtils.mkdir_p(CACHE_DIR)
    end
                def analyze
      if cache_valid?
        puts "Loading from cache..."
        load_from_cache
        display_results
        return
      end

      puts "Analyzing #{@path}..."
      scan_large_files
      scan_medium_files
      scan_directories
      @aggregated_directories = aggregate_by_directory(@large_files + @medium_files)
      save_to_cache
      display_results
    end

    private

    def scan_large_files
      puts "Scanning for large files..."
      cmd = "mdfind -onlyin '#{@path}' \"kMDItemFSSize > #{MIN_LARGE_FILE_SIZE}\""
      stdout, stderr, status = Open3.capture3(cmd)

      return unless status.success?

      stdout.each_line do |line|
        path = line.strip
        size = File.size(path)
        @large_files << { path: path, size: size }
      end

      @large_files.sort_by! { |f| -f[:size] }
    end

    def scan_medium_files
      puts "Scanning for medium files..."
      cmd = "mdfind -onlyin '#{@path}' \"kMDItemFSSize > #{MIN_MEDIUM_FILE_SIZE} && kMDItemFSSize < #{MIN_LARGE_FILE_SIZE}\""
      stdout, stderr, status = Open3.capture3(cmd)

      return unless status.success?

      stdout.each_line do |line|
        path = line.strip
        size = File.size(path)
        @medium_files << { path: path, size: size }
      end

      @medium_files.sort_by! { |f| -f[:size] }
    end

    def scan_directories
      puts "Scanning directories..."
      cmd = "du -d 1 -k '#{@path}'"
      stdout, stderr, status = Open3.capture3(cmd)

      return unless status.success?

      stdout.each_line do |line|
        size, path = line.split("\t")
        next if path.strip == @path
        @directories << { path: path.strip, size: size.to_i * 1024 }
      end

      @directories.sort_by! { |d| -d[:size] }
    end

            def display_results
      puts "\n--- Top 10 Large Files ---"
      @large_files.first(10).each do |file|
        puts "#{format_bytes(file[:size])}\t#{file[:path]}"
      end

      puts "\n--- Top 10 Medium Files ---"
      @medium_files.first(10).each do |file|
        puts "#{format_bytes(file[:size])}\t#{file[:path]}"
      end

      puts "\n--- Top 10 Directories ---"
      @directories.first(10).each do |dir|
        puts "#{format_bytes(dir[:size])}\t#{dir[:path]}"
      end

      puts "\n--- Top 10 Aggregated Directories ---"
      @aggregated_directories.first(10).each do |dir|
        puts "#{format_bytes(dir[:size])} in #{dir[:count]} files\t#{dir[:path]}"
      end
    end

                def cache_valid?
      cache_file = "#{CACHE_DIR}/#{@path_hash}.cache"
      return false unless File.exist?(cache_file)
      (Time.now - File.mtime(cache_file)) < 3600 # 1 hour
    end

    def save_to_cache
      cache_file = "#{CACHE_DIR}/#{@path_hash}.cache"
      data = {
        large_files: @large_files,
        medium_files: @medium_files,
        directories: @directories,
        aggregated_directories: @aggregated_directories
      }
      File.write(cache_file, Marshal.dump(data))
    end

    def load_from_cache
      cache_file = "#{CACHE_DIR}/#{@path_hash}.cache"
      data = Marshal.load(File.read(cache_file))
      @large_files = data[:large_files]
      @medium_files = data[:medium_files]
      @directories = data[:directories]
      @aggregated_directories = data[:aggregated_directories]
    end

    def format_bytes(bytes)
      return "0B" if bytes.zero?
      units = ["B", "KB", "MB", "GB", "TB"]
      i = (Math.log(bytes) / Math.log(1024)).floor
      "%.2f%s" % [bytes.to_f / 1024**i, units[i]]
    end

    def aggregate_by_directory(files)
      directories = Hash.new { |h, k| h[k] = { size: 0, count: 0 } }

      files.each do |file|
        dir = File.dirname(file[:path])
        directories[dir][:size] += file[:size]
        directories[dir][:count] += 1
      end

      directories.map do |path, data|
        { path: path, size: data[:size], count: data[:count] }
      end.sort_by! { |d| -d[:size] }
    end
  end
end
