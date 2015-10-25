require File.expand_path('../guide_doc', __FILE__)

class Module::TopicDoc

  attr_accessor :path, :sub_topics, :guides

  def initialize(path, output_dir_root, guides_output_dir)
    @output_dir_root = output_dir_root
    @guides_output_dir = guides_output_dir

    self.path = path
    self.sub_topics = {}
    self.guides = []
  end

  def add_guide(guide_doc)
    guides << guide_doc
  end

  def write
    topic_dir = File.join(@guides_output_dir, path)
    FileUtils.mkdir_p topic_dir

    base_path = Pathname.new( @output_dir_root )
    relative_to_base = base_path.relative_path_from( Pathname.new(topic_dir) )

    page = TopicPage.new(path, self, relative_to_base)

    File.open(File.join(topic_dir, "index.html"), 'w') { |f| f.write(page.render('templates/guide/topic_doc')) }
  end

end
