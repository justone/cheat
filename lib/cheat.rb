$:.unshift File.dirname(__FILE__)
%w[rubygems pp tempfile fileutils net/http yaml open-uri wrap].each { |f| require f }

module Cheat
  extend self

  @cheat_urls = ["http://cheat.endot.org:1337/", "http://localhost:8020/"]
  #@cheat_urls = ["http://cheat.endot.org:1337/", "http://cheat.errtheblog.com/"]

  def sheets(args)
    args = args.dup

    return unless parse_args(args)

    FileUtils.mkdir(cache_dir) unless File.exists?(cache_dir) if cache_dir

    uri = "y/"

    if %w[sheets all recent].include? @sheet
      uri = uri.sub('y/', @sheet == 'recent' ? 'yr/' : 'ya/')
      return @cheat_urls.each do |base_uri|
        open(base_uri + uri) { |body| show(body.read) } 
      end
    end

    return show(File.read(cache_file)) if File.exists?(cache_file) rescue clear_cache if cache_file 

    fetch_sheet(uri + @sheet) if @sheet
  end

  def fetch_sheet(uri, try_to_cache = true)
    @cheat_urls.each do |base_uri|
      @current_base_uri = base_uri
      #puts base_uri + uri
      begin
        open(base_uri + uri, headers) do |body|
          sheet = body.read
          next if sheet =~ /not found/
          File.open(cache_file, 'w') { |f| f.write(sheet) } if try_to_cache && cache_file && !@edit 
          @edit ? edit(sheet) : show(sheet)
          return
        end 
      rescue Exception => e
        puts "Whoa, some kind of Internets error!", "=> #{e} from #{base_uri + uri}"
      end
    end

    puts "Hm... a cheat sheet for '#{@sheet}' doesn't seem to exist.  Care to share?"
  end

  def parse_args(args)
    puts "Looking for help?  Try http://cheat.errtheblog.com or `$ cheat cheat'" and return if args.empty?

    if args.delete('--clear-cache') || args.delete('--new')
      clear_cache
      return if args.empty?
    end

    if i = args.index('--diff')
      diff_sheets(args.first, args[i+1]) 
    end

    show_versions(args.first) if args.delete('--versions')

    add(args.shift) and return if args.delete('--add')
    clear_cache if @edit = args.delete('--edit')

    @sheet = args.shift

    true
  end

  # $ cheat greader --versions
  def show_versions(sheet)
    fetch_sheet("h/#{sheet}/", false)
  end

  # $ cheat greader --diff 1[:3]
  def diff_sheets(sheet, version)
    return unless version =~ /^(\d+)(:(\d+))?$/
    old_version, new_version = $1, $3

    uri = "d/#{sheet}/#{old_version}"
    uri += "/#{new_version}" if new_version

    fetch_sheet(uri, false) 
  end

  def cache_file
    "#{cache_dir}/#{@sheet}.yml" if cache_dir
  end

  def headers
    { 'User-Agent' => 'cheat!', 'Accept' => 'text/yaml' } 
  end

  def show(sheet_yaml)
    sheet = YAML.load(sheet_yaml).to_a.first
    #pp sheet
    sheet[-1] = sheet.last.join("\n") if sheet[-1].is_a?(Array)
    run_pager
    puts sheet.first + ':'
    puts '  ' + sheet.last.gsub("\r",'').gsub("\n", "\n  ").wrap
  rescue Errno::EPIPE
    # do nothing
  rescue
    puts "That didn't work.  Maybe try `$ cheat cheat' for help?" # Fix Emacs ruby-mode highlighting bug: `"
  end

  def edit(sheet_yaml)
    sheet = YAML.load(sheet_yaml).to_a.first
    sheet[-1] = sheet.last.gsub("\r", '')
    body, title = write_to_tempfile(*sheet), sheet.first
    return if body.strip == sheet.last.strip
    res = post_sheet(title, body)
    check_errors(res, title, body)
  end

  def add(title)
    body = write_to_tempfile(title)
    @current_base_uri = @cheat_urls.first # TODO: figure out which host to write to
    res = post_sheet(title, body, true)
    check_errors(res, title, body)
  end

  def post_sheet(title, body, new = false)
    uri = "#{@current_base_uri}w/"
    puts uri
    uri += title unless new
    Net::HTTP.post_form(URI.parse(uri), "sheet_title" => title, "sheet_body" => body.strip, "from_gem" => true)
  end

  def write_to_tempfile(title, body = nil)
    # god dammit i hate tempfile, this is so messy but i think it's
    # the only way.
    tempfile = Tempfile.new(title + '.cheat')
    tempfile.write(body) if body
    tempfile.close
    system "#{editor} #{tempfile.path}"
    tempfile.open
    body = tempfile.read
    tempfile.close
    body
  end

  def check_errors(result, title, text)
    if result.body =~ /<p class="error">(.+?)<\/p>/m
      puts $1.gsub(/\n/, '').gsub(/<.+?>/, '').squeeze(' ').wrap(80)
      puts 
      puts "Here's what you wrote, so it isn't lost in the void:" 
      puts text
    else
      puts "Success!  Try it!", "$ cheat #{title} --new"
    end
  end

  def editor
    ENV['VISUAL'] || ENV['EDITOR'] || "vim" 
  end

  def cache_dir
    PLATFORM =~ /win32/ ? win32_cache_dir : File.join(File.expand_path("~"), ".cheat")
  end

  def win32_cache_dir
    unless File.exists?(home = ENV['HOMEDRIVE'] + ENV['HOMEPATH'])
      puts "No HOMEDRIVE or HOMEPATH environment variable.  Set one to save a" +
           "local cache of cheat sheets."
      return false
    else
      return File.join(home, 'Cheat')
    end
  end

  def clear_cache
    FileUtils.rm_rf(cache_dir) if cache_dir
  end

  def run_pager
    return if PLATFORM =~ /win32/
    return unless STDOUT.tty?

    read, write = IO.pipe

    unless Kernel.fork # Child process
      STDOUT.reopen(write)
      STDERR.reopen(write) if STDERR.tty?
      read.close
      write.close
      return
    end

    # Parent process, become pager
    STDIN.reopen(read)
    read.close
    write.close

    ENV['LESS'] = 'FSRX' # Don't page if the input is short enough

    # wait until we have input before we start the pager
    Kernel.select [STDIN]
    pager = ENV['PAGER'] || 'less'
    exec pager rescue exec "/bin/sh", "-c", pager
  rescue
  end
end

Cheat.sheets(ARGV) if __FILE__ == $0
