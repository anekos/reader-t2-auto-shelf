# vim: set fileencoding=utf-8 :


require 'sqlite3'
require 'uri'
require 'base64'
require 'term/ansicolor'
require 'time'

include Term::ANSIColor

module PathUtil
  def self.escape_path (path)
    res = []
    P(path).ascend {|it| res << self.escape(it.basename.to_s) }
    P(res.last).join(*(res[0...-1].reverse))
  end

  def self.escape (s)
    s.to_s.split(/\./).map do
      |it|
      if it.bytes.all? {|c| (0x20 .. 0x7e) === c }
        it
      else
        opts = {:undef => :replace, :invalid => :replace, :replace => '='}
        Base64.encode64(it.encode('CP932', opts).to_s).gsub(/\n/, '').tr('/', '-')
      end
    end.join('.')
  end
end

class ShelfContent < Struct.new(:type, :filepath, :filename, :size)
  attr_accessor :id

  def title
    self.filename.sub_ext('').to_s.sub(/\A\[[^\]]+\]\s*/, '')
  end

  def author
    self.filename.to_s.match(/\A\[([^\]]+)\]/).to_a[1]
  end
end

class Project
  attr_accessor :body_source_path
  attr_accessor :sd_source_path
  attr_accessor :body_path
  attr_accessor :sd_path
  attr_accessor :sub_directory

  def initialize
  end

  def run
    dbfile = dbfile_path
    SQLite3::Database.open(dbfile.to_s) do
      |db|
      db.results_as_hash = true
      @db = db

      reset
      check!
      copy(:body, @body_source_path, @body_path) if @body_source_path and @body_path
      copy(:sd, @sd_source_path, @sd_path) if @sd_source_path and @sd_path
      make_shelf_all

      @db = nil
    end
  end

  private

  def dbfile_path
    @body_path.join('Sony_Reader', 'database', 'books.db')
  end

  def check!
    throw "No Database file: #{dbfile_path}" unless dbfile_path.exist?
  end

  def reset
    @shelf = {}
  end

  def copy (type, src, dest)
    put_phase("Copy: #{type}")
    Dir.entries(src).each do
      |it|
      next if /\A\.+\Z/ === it
      copy_files(type, src, dest, P(it))
    end
  end

  def copy_files (type, src, dest, shelf)

    shelfContents = @shelf[shelf.to_s] = []
    results = Struct.new(:ok, :fail).new([], [])

    (src + shelf).entries.each do
      |book|
      next unless (src + shelf + book).file?
      next unless %w[epub pdf].include?(book.extname.downcase.sub(/\A\./, ''))
      put_now(book)
      src_file = src + shelf + book
      dest_file = @sub_directory + PathUtil.escape_path(shelf + book)
      dest_file = dest_file.sub_ext('.kepub.epub') if 'epub' === dest_file.extname
      put_result(dest_file.to_s)
      FileUtils.mkdir_p((dest + dest_file).parent)
      content = ShelfContent.new(type, dest_file, book, src_file.size)
      shelfContents << content
      if copy_file(src_file, dest + dest_file)
        update_content(content)
        put_result('copied.'.bold.on_blue)
      else
        put_result('skipped.'.on_red)
      end
    end
  end

  def copy_file (src, dest)
    return false if dest.exist? and src.size == dest.size # and src.mtime == dest.mtime
    FileUtils.cp(src, dest)
    return true
  end

  def update_content (content)
    book = @db.execute('select _id from books where file_path = ?', content.filepath.to_s).first
    date = Time.now.to_i * 1000
    if book
      id = book['_id']
      @db.execute(
        'update books ' +
        'set modified_date = ? ' +
        'where _id = ?',
        date, id
      )
      content.id = id
    else
      max_id = @db.execute('select max(_id) as max from books').first['max']
      next_id = max_id + 1
      content.id = next_id
      mime_type =
        case content.filepath.extname
        when /pdf/i
          'application/pdf'
        when /epub/i
          'application/epub+zip'
        end
      @db.execute(
        'insert into books' +
        '(_id, title, author, source_id, added_date, modified_date, file_path, file_name, file_size, mime_type, prevent_delete)' +
        'values (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, 0)',
        next_id, content.title, content.author, date, date, content.filepath.to_s, content.filepath.basename.to_s, content.size, mime_type
      )
    end
  end

  def make_shelf_all
    @shelf.each do
      |name, contents|
      put_phase("Make Shelf: #{name}")
      make_shelf(name, contents)
    end
  end

  def make_shelf (name, contents)
    col = @db.execute('select * from collection where title = ?', name)
    collection_id =
      if col.empty?
        max_id = @db.execute('select max(_id) as max from collection').first['max']
        next_id = (max_id || 0) + 1
        @db.execute(
          'insert into collection' +
          '(_id, title, source_id)' +
          'values (?, ?, 0)',
          next_id, name
        )
        next_id
      else
        col.first['_id']
      end

    contents.each do
      |content|
      unless content.id
        book = @db.execute('select _id from books where file_path = ?', content.filepath.to_s).first
        content.id = book['_id']
      end
      if @db.execute('select * from collections where content_id = ?', content.id).empty?
        max_id = @db.execute('select max(_id) as max from collections').first['max']
        next_id = (max_id || 0) + 1
        @db.execute('insert into collections (_id, collection_id, content_id) values (?, ?, ?)', next_id, collection_id, content.id)
      else
        @db.execute('update collections set collection_id = ? where content_id = ?', collection_id, content.id)
      end
    end
  end

  def put_phase (name)
    STDOUT.puts("[#{name}]")
  end

  def put_now (name)
    STDOUT.puts(" -> #{name}")
  end

  def put_result (name)
    STDOUT.puts(" => #{name}")
  end
end

def P (path)
  if Pathname === path
    path
  else
    Pathname.new(path.to_s)
  end
end

class OptionParser
  def self.parse (args)
    require 'ostruct'
    require 'optparse'

    op = OpenStruct.new

    parser = OptionParser.new do
      |parser|
      parser.banner = "Usage: #{File.basename($0)} [options]"

      parser.on('--body <BODY_DRIVE_PATH>') { |it| op.body = P(it) }
      parser.on('--sd <SD_DRIVE_PATH>') { |it| op.sd = P(it) }
      parser.on('--sub <SUB_DIRECTORY_NAME>') { |it| op.sub_directory = P(it) }
      parser.on('--body-source <BODY_SYNC_source>') { |it| op.body_source = P(it) }
      parser.on('--sd-source <SD_SYNC_source>') { |it| op.sd_source = P(it) }
    end

    parser.parse!(args)

    raise unless op.body and (op.body_source or (op.sd and op.sd_source))

    op
  rescue => e
    puts e
    puts parser.help
    exit
  end
end

options = OptionParser.parse(ARGV)
proj = Project.new
proj.body_path = options.body
proj.sd_path = options.sd
proj.sub_directory = options.sub_directory || P('')
proj.body_source_path = options.body_source
proj.sd_source_path = options.sd_source
proj.run
