class Module::GuideDoc

  attr_accessor :path, :name, :data

  def initialize(path, output_dir_root, guides_output_dir)
    @output_dir_root = output_dir_root
    @guides_output_dir = guides_output_dir

    self.path = File.split(path).first
    self.name = File.split(path).last.split(".").first
    self.data = {}
    parse_metadata
  end

  def parse_metadata
    contents = File.open(File.join("guides", path, "#{name}.md"), "r")
    while(1)
      contents.gets
      break if $_.chomp == "!------" or $_.nil?
      matches = $_.scan(/(.*):\s*(.*)/)
      matches.each do |match|
        self.data[match[0].to_sym] = match[1].chomp
      end
    end
  end

  def url(relative_base)
    relative_base == "" ? "guides/#{path}/#{name}.html" : "#{relative_base}/guides/#{path}/#{name}.html"
  end

  def write
    base_path = Pathname.new( @output_dir_root )
    guide_dir = File.join(@guides_output_dir, path)

    relative_to_base = base_path.relative_path_from( Pathname.new(guide_dir) )
    guide_page = GuidePage.new(guide_dir, self, relative_to_base)

    FileUtils.mkdir_p guide_dir unless File.exists? guide_dir

    File.open(File.join(guide_dir, "#{name}.html"), 'w') do |f|
      f.write(guide_page.render File.expand_path("templates/guide/guide_page"))
    end
  end

  def to_s
    name
  end

end
