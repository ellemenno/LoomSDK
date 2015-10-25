# load gemfiles
require 'bundler/setup'
require 'rubygems'

# require everything else
require 'erb'
require 'fileutils'
# require 'ostruct'
require 'pathname'
# require 'pp'
require 'pygments'

require 'pry'

require File.expand_path('../example_doc', __FILE__)
require File.expand_path('../guide_doc', __FILE__)
require File.expand_path('../guide_tree', __FILE__)
require File.expand_path('../loom_lib', __FILE__)
require File.expand_path('../package_doc', __FILE__)
require File.expand_path('../package_tree', __FILE__)
require File.expand_path('../topic_doc', __FILE__)
require File.expand_path('../../renderer/class_page', __FILE__)
require File.expand_path('../../renderer/example_index', __FILE__)
require File.expand_path('../../renderer/example_page', __FILE__)
require File.expand_path('../../renderer/guide_page', __FILE__)
require File.expand_path('../../renderer/home_page', __FILE__)
require File.expand_path('../../renderer/package_page', __FILE__)
require File.expand_path('../../renderer/page', __FILE__)
require File.expand_path('../../renderer/topic_page', __FILE__)


module LoomDocs
  VERSION = '0.0.1'
end

# OUTPUT_DIR = "output"
# API_OUTPUT_DIR = File.join(OUTPUT_DIR, "api")
# EXAMPLES_OUTPUT_DIR = File.join(OUTPUT_DIR, "examples")
# GUIDES_OUTPUT_DIR = File.join(OUTPUT_DIR, "guides")

# ARG_VERSION = 0

def api_output_dir
  File.join(@output_dir_root, "api")
end

def examples_output_dir
  File.join(@output_dir_root, "examples")
end

def guides_output_dir
  File.join(@output_dir_root, "guides")
end

@packages = nil
@stats = {}
@subclasses_of_base_type = {}

$classes_by_package_path = {}
$examples = {}
$guides = nil
$packages = @packages
$search_json = ''

def generate(options = {})
  @output_dir_root = options.fetch(:output, 'output')
  FileUtils.rm_rf @output_dir_root
  FileUtils.mkdir_p @output_dir_root
  FileUtils.cp_r Dir['static/*'], @output_dir_root

  @packages = PackageTree.new(@output_dir_root, api_output_dir)
  $guides = GuideTree.new(@output_dir_root, guides_output_dir)

  puts "Generating Loomdocs for #{version_number}"
  puts "== Processing loomlibs =="
  process_loomlibs(options.fetch(:libs, '../artifacts/libs'))

  puts "== Copying examples =="
  copy_examples(options.fetch(:examples, 'examples'))

  puts "== Processing guides =="
  process_guides(options.fetch(:guides, 'guides'))

  puts "== Generating Docs =="
  generate_search_data
  write_packages
  write_examples
  write_guides
  write_landing_page

  puts "== #{@stats[:num_classes]} classes; #{@stats[:num_examples]} examples; #{@stats[:num_guides]} guides =="
end

def copy_examples(examples_source_dir)
  FileUtils.cp_r(Dir.glob(examples_source_dir), @output_dir_root)
  Dir["#{examples_source_dir}/*"].each do |lib_path|
    example_doc = Module::ExampleDoc.new(lib_path.split("/").last, @output_dir_root, examples_output_dir)
    puts "Processing #{example_doc.path}.."
    $examples[example_doc.name] = example_doc
  end
end

def process_loomlibs(loomlibs_dir)
  Dir["#{loomlibs_dir}/*.loomlib"].each do |lib_path|
    puts "Processing #{lib_path}"

    lib = LoomLib.new(lib_path)
    lib.modules.each do |this_module|

      this_module.types.each do |class_doc|

        if class_doc.data[:docString].include? "@private"
          puts "  skipping private class: #{class_doc.package_path}"
          next
        end

        # Store each class, keyed to its package_path, so we can derive its superclasses later.
        $classes_by_package_path[ class_doc.package_path ] = class_doc

        # Loop through packages
        package = class_doc.data[:package]
        @packages[package] = Module::PackageDoc.new(package, @output_dir_root, api_output_dir) if @packages[package].nil?
        @packages[package].assign_doc(class_doc)

        # Store all subclasses of a particular base type.
        @subclasses_of_base_type[ class_doc.data[:baseType] ] = [] unless @subclasses_of_base_type.has_key? class_doc.data[:baseType]
        @subclasses_of_base_type[ class_doc.data[:baseType] ] << class_doc
      end

    end
  end
end

def process_guides(guides_dir)
  puts "Generating guides for #{guides_dir}/.."

  Dir.glob("#{guides_dir}/*") do |filename|
    # next if filename == "." or filename == ".." or filename == guides_dir
    if File.directory? filename
      process_guides filename
    elsif $guides[filename].nil?
      filename.gsub! "guides/", ""
      $guides[File.split(filename).first] = Module::TopicDoc.new(File.split(filename).first, @output_dir_root, guides_output_dir)
      $guides[File.split(filename).first].add_guide Module::GuideDoc.new(filename, @output_dir_root, guides_output_dir)
    else
      filename.gsub! "guides/", ""
      $guides[File.split(filename).first].add_guide Module::GuideDoc.new(filename, @output_dir_root, guides_output_dir)
    end
  end
end

def generate_search_data
  puts "Generating search data.."

  classes = []
  sorted_classes = $classes_by_package_path.values.sort { |a, b| a.data[:name] <=> b.data[:name] }
  sorted_classes.each do |value|
    classes << { :path => "api.#{value.data[:package]}.#{value.data[:name]}", :name => value.data[:name] }
  end

  examples = []
  sorted_examples = $examples.values.sort { |a, b| a.path <=> b.path }
  sorted_examples.each do |example_doc|
    examples << { :path => "examples.#{example_doc.path}.index", :name => example_doc.data[:title] }
  end

  guides = []
  $guides.each do |topic_doc|
    topic_doc.guides.each do |guide_doc|
      guides << { :path => "guides.#{guide_doc.path}.#{guide_doc.name}", :name => guide_doc.data[:title] }
    end
  end

  @stats[:num_classes] = classes.length
  @stats[:num_examples] = examples.length
  @stats[:num_guides] = guides.length

  $search_json = JSON.dump( { :classes => classes, :examples => examples, :guides => guides } )

  File.open("output/manifest.json", "w") { |file| file.write($search_json) }
end

def write_class_file(class_doc)
  return if class_doc.nil?

  puts "  writing #{class_doc.data[:name]}"

  class_dir = File.join( api_output_dir, class_doc.data[:package].split('.') )
  FileUtils.mkdir_p class_dir

  subclasses = @subclasses_of_base_type.has_key?( class_doc.package_path ) ? @subclasses_of_base_type[ class_doc.package_path ] : []

  base_path = Pathname.new( @output_dir_root )
  relative_to_base = base_path.relative_path_from( Pathname.new(class_dir ) )

  constants = class_doc.get_constants.values
  public_fields = class_doc.get_fields( 'public' ).values
  public_methods = class_doc.get_methods( 'public' ).values
  protected_fields = class_doc.get_fields( 'protected' ).values
  protected_methods = class_doc.get_methods( 'protected' ).values
  events = class_doc.get_events

  # Alphabetize
  constants = constants.sort_by { |f| f[:name] }
  public_fields = public_fields.sort_by { |f| f[:name] }
  public_methods = public_methods.sort_by { |f| f[:name] }
  protected_fields = protected_fields.sort_by { |f| f[:name] }
  protected_methods = protected_methods.sort_by { |f| f[:name] }
  events = events.sort_by { |e| e[:name] }

  page = ClassPage.new(class_doc, class_doc.superclasses, subclasses, base_path, relative_to_base, constants, public_fields, protected_fields, public_methods, protected_methods, events)

  # TODO: Use a switch statement on the doc type to determine which template to use.
  File.open(File.join(class_dir, "#{class_doc.data[:name]}.html"), 'w') {|f| f.write(page.render('templates/class_doc')) }
end

def write_packages
  puts "Generating packages and classes"


  # loop through packages
  @packages.each do |package_doc|
    puts "Processing #{package_doc.path}"
    binding.pry()
    package_doc.write
    package_doc.all_class_docs.each { |class_doc| write_class_file(class_doc) }
  end
end

def write_examples
  puts "Writing Examples"

  $examples.each do |key, example_doc|
    puts "  writing #{example_doc.path}"
    example_doc.write
  end

  write_example_index
end

def write_guides
  puts "Writing Guides"

  $guides.each do |topic_doc|
    puts "  writing #{topic_doc.path}"
    topic_doc.write
    topic_doc.guides.each { |guide_doc| guide_doc.write }
  end
end

def write_example_index
  puts "Writing Examples Index"

  relative_base_path = Pathname.new(@output_dir_root).relative_path_from( Pathname.new(examples_output_dir) )
  index_page = ExampleIndex.new($examples, version_number, relative_base_path)

  File.open(File.join(examples_output_dir, "index.html"), 'w') do |f|
    f.write(index_page.render File.expand_path("templates/example/example_index"))
  end
end

def write_landing_page
  puts "Writing Home Page"

  home_page = HomePage.new(version_number, './')

  File.open(File.join(@output_dir_root, "index.html"), 'w') do |f|
    f.write(home_page.render File.expand_path("templates/home"))
  end
end

def version_number
  ENV.fetch('LOOM_VERSION', '???')
end

