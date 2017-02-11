#!/usr/bin/env ruby
#
# inspired by https://github.com/omakoto/zenlog

require 'fileutils'
require 'tempfile'

TANLOG_DIR = '/tmp/tanlog'

ZSH_CODE = <<EOC
tanlog_begin() {
    export TANLOG_LOGFILE=$($HOME/test/tanlog.rb start $1)
}
tanlog_end() {
    $HOME/test/tanlog.rb end $TANLOG_LOGFILE
}
typeset -Uga preexec_functions
typeset -Uga precmd_functions
preexec_functions+=tanlog_begin
precmd_functions+=tanlog_end
EOC

Encoding.default_external = 'binary'
Encoding.default_internal = 'binary'

def human(n)
  if n >= 10_000_000_000
    "#{(n/1000_000_000).to_i}G"
  elsif n >= 10_000_000
    "#{(n/1000_000).to_i}M"
  elsif n >= 10_000
    "#{(n/1000).to_i}k"
  else
    "#{n}"
  end
end

def screen(args)
  if !system("screen #{args * ' '}")
    raise "command failed: #{args}"
  end
end

def raw_to_san(rawfile)
  rawfile.sub('/RAW/', '/')
end

def create_prev_links(logfile, dir)
  9.downto(1){|n|
    prev_link = "#{dir}/" + "P" * n
    if File.exist?(prev_link)
      File.rename(prev_link, prev_link + "P")
    end
  }
  FileUtils.ln_sf(logfile, "#{dir}/P")
end

def setup_cmd_link(logfile, cmd)
  arg0 = cmd.sub(/^[()\s]+/, '').split[0]
  arg0 = File.basename(arg0)
  ["#{TANLOG_DIR}/RAW/#{arg0}",
   "#{File.dirname(logfile)}/#{arg0}"].each do |cmddir|
    [[cmddir, logfile],
     [raw_to_san(cmddir), raw_to_san(logfile)]].each do |cd, lf|
      FileUtils.mkdir_p(cd)
      dest = "#{cd}/#{File.basename(lf)}"
      FileUtils.ln_sf(lf, dest)

      create_prev_links(lf, cd)
    end
  end
end

def setup_log(cmd)
  now = Time.now
  date = now.strftime('%Y-%m-%d')
  logdir = "#{TANLOG_DIR}/RAW/#{date}"
  FileUtils.mkdir_p(logdir)
  FileUtils.mkdir_p(raw_to_san(logdir))

  FileUtils.rm_f("#{TANLOG_DIR}/.TODAY")
  FileUtils.ln_sf(raw_to_san(logdir), "#{TANLOG_DIR}/.TODAY")
  File.rename("#{TANLOG_DIR}/.TODAY", "#{TANLOG_DIR}/TODAY")

  FileUtils.rm_f("#{TANLOG_DIR}/RAW/.TODAY")
  FileUtils.ln_sf(logdir, "#{TANLOG_DIR}/RAW/.TODAY")
  File.rename("#{TANLOG_DIR}/RAW/.TODAY", "#{TANLOG_DIR}/RAW/TODAY")

  time = now.strftime('%H:%M:%S')
  n = 0
  while true
    logfile = "#{logdir}/#{time}-#{n}.log"
    break if !File.exist? logfile
    n += 1
  end

  File.open(logfile, 'w') do |of|
    of.puts "$ #{cmd}"
  end

  screen(['-X', 'logfile', logfile])
  screen(['-X', 'log', 'on'])

  print logfile

  create_prev_links(raw_to_san(logfile), "#{TANLOG_DIR}/TODAY")
  setup_cmd_link(logfile, cmd)
end

def start_tanlog(args)
  setup_log(args[0])
end

def sanitize_log(rawfile)
  sanfile = raw_to_san(rawfile)
  return if File.exist?(sanfile)

  File.open(rawfile) do |ifile|
    File.open(sanfile, 'w') do |of|
      ifile.each do |log|
        log.gsub!(/\a                        # Bell
                  | \e \x5B .*? [\x40-\x7E]  # CSI
                  | \e \x5D .*? \x07         # Set terminal title
                  | \e [\x40-\x5A\x5C\x5F]   # 2 byte sequence
                  /x, '')
        log.gsub!(/\s* \x0d* \x0a/x, "\x0a")  # Remove end-of-line CRs.
        log.gsub!(/ \s* \x0d /x, "\x0a")      # Replace orphan CRs with LFs.

        of.print log
      end
    end
  end
end

def end_tanlog(args)
  screen(['-X', 'log', 'off'])
  fname = args[0]
  if fname && File.size(fname) < 100_000_000
    sanitize_log(fname)
  end
end

def show_recent_logs(args)
  logs = Dir.glob("#{TANLOG_DIR}/TODAY/P*").sort
  logs.reverse.each do |log|
    print File.read(log)
  end
end

def show_recent_paths(args)
  logs = Dir.glob("#{TANLOG_DIR}/RAW/TODAY/*").sort
  paths = []
  logs.reverse.each do |log|
    next if log !~ /\.log$/ || !File.file?(log)
    cmdline, *lines = File.readlines(log)
    cmd = cmdline.split[1]
    next if cmd == 'wl' || cmdline =~ /tanlog/

    lines.reverse.each do |line|
      if line =~ /https?:\/\/[\S&&[:print:]]+\/[\S&&[:print:]]+/
        paths << "#{$&} in #{cmd}@#{log}"
      elsif line =~ /(^|\s)(\/[\S&&[:print:]]+\/[\S&&[:print:]]+)/
        path = $2
        if File.exist?(path)
          paths << "#{path} in #{cmd}@#{log}"
        end
      end
    end
    paths.uniq!
    if paths.size >= 100
      break
    end
  end
  puts paths * "\n"
end

def gc(args)
  dry_run = args[0] != '-f'
  size = 0
  cnt = 0
  total_size = 0
  total_cnt = 0

  basedirs = [TANLOG_DIR, "#{TANLOG_DIR}/RAW"]
  basedirs.each do |basedir|
    Dir.foreach(basedir).sort.each do |datedir|
      if datedir !~ /(\d\d\d\d)-(\d\d)-(\d\d)/
        next
      end
      date = Time.mktime($1.to_i, $2.to_i, $3.to_i)
      elapsed = Time.now - date
      datedir = basedir + "/" + datedir

      Dir.glob("#{datedir}/*.log").sort.each do |log|
        sz = File.size(log)
        total_size += sz
        total_cnt += 1
        if (sz > 100_000_000 ||
            sz > 1_000_000 && elapsed > 14 * 24 * 60 * 60)
          size += sz
          cnt += 1
          if !dry_run
            File.unlink(log)
          end
        end
      end
    end
  end

  report = "#{human(size)}B/#{human(total_size)} (#{cnt}/#{total_cnt} files)"
  if dry_run
    puts "will remove #{report}"
  else
    puts "removed #{report}"
  end
end

cmd, *args = ARGV

case cmd
when 'start'
  exit if ENV['TERM'] !~ /screen/ || ENV['SSH_TTY']
  start_tanlog(args)
when 'end'
  exit if ENV['TERM'] !~ /screen/ || ENV['SSH_TTY']
  end_tanlog(args)
when 'recent'
  show_recent_logs(args)
when 'paths'
  show_recent_paths(args)
when 'gc'
  gc(args)
else
  raise "Unknown tanlog command: #{cmd}"
end
