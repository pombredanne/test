require 'json'
require 'open-uri'

$URL_BASE = 'https://ark.intel.com/'

def scrape_detail(url)
  STDERR.puts url
  data = {}
  open(url, 'r:utf-8', &:read).scan(/<span class="value" data-key="(.*?)">(.*?)<\/span>/m) do
    data[$1] = $2.strip
  end
  return data
end

def scrape_nucs(url)
  rows = []
  open(url, 'r:utf-8', &:read).scan(/<tr .*?<\/tr>/m) do
    cols = []
    $&.scan(/<td.*?>(.*?)<\/td>/m) do
      cols << $1.strip
    end
    rows << cols
  end

  nucs = []
  rows.each do |cols|
    nuc = cols[0]
    cpu = cols[2]
    nuc_url = nuc[/"(.*?)"/, 1]
    nuc_name = nuc[/>(.*?)<\/a>/, 1]
    nuc_name = nuc_name[/NUC\d\w+/, 0]
    cpu_url = cpu[/"(.*?)"/, 1]
    cpu_name = cpu[/ (i\d-\d+\w) Processor<\/a>/, 1]

    nucs << [nuc_url, nuc_name, cpu_url, cpu_name]
  end

  cpu_details = {}
  nucs.map do |nuc|
    next if cpu_details[nuc[2]]
    cpu_details[nuc[2]] = scrape_detail("#{$URL_BASE}#{nuc[2]}")
    #break
  end

  nuc_details = {}
  nucs.map do |nuc|
    next if nuc_details[nuc[0]]
    nuc_details[nuc[0]] = scrape_detail("#{$URL_BASE}#{nuc[0]}")
    #break
  end

  [nucs, nuc_details, cpu_details]
end

urls = [
  ['7th', "#{$URL_BASE}content/www/us/en/ark/products/series/129702/intel-nuc-mini-pc-with-7th-generation-intel-core-processors.html"],
  ['8th', "#{$URL_BASE}content/www/us/en/ark/products/series/129701/intel-nuc-mini-pc-with-8th-generation-intel-core-processors.html"],
]

if true
  nucs = []
  urls.each do |typ, _|
    data = JSON.load(File.open("nucs-#{typ}.json", 'r:utf-8', &:read))
    raw_nucs, nuc_details, cpu_details = data
    raw_nucs.each do |nuc_path, nuc_name, cpu_path, cpu_name|
      nuc_detail = nuc_details[nuc_path]
      cpu_detail = cpu_details[cpu_path]
      raise if !nuc_detail
      raise if !cpu_detail

      nuc = []
      nuc << nuc_name
      nuc << cpu_name
      nuc << ''
      nuc << ''
      nuc << nuc_detail['MaxTDP']
      nuc << cpu_detail['CoreCount']
      clock = cpu_detail['ClockSpeed'].gsub(/GHz/, '').strip
      nuc << clock
      turbo = cpu_detail['ClockSpeedMax']
      turbo = turbo ? turbo.gsub(/GHz/, '').strip : clock
      nuc << turbo
      gpu = cpu_detail['ProcessorGraphicsModelId']
      if gpu
        gpu.gsub!(/[^ a-zA-Z0-9]/, '')
        gpu.gsub!(/Intel /, '')
        gpu.gsub!(/Graphics /, '')
      else
        gpu = 'N/A'
      end
      nuc << gpu

      nucs << nuc
    end
  end

  tbl = [%w(name chip price gflops/sec watt cores clock turbo gpu)]
  nucs.each do |row|
    tbl << row
  end

  tbl.each do |row|
    puts row * ','
  end

else
  urls.each do |typ, url|
    data = scrape_nucs(url)
    File.open("nucs-#{typ}.json", 'w') do |of|
      of.puts(JSON.dump(data))
    end
  end
end
