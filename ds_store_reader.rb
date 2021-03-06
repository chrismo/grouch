require 'ostruct'

# reference: http://search.cpan.org/~wiml/Mac-Finder-DSStore/DSStoreFormat.pod
#
# Also, I know, I know, this is LOL parsing ... I was studying jazz, not computer science.
class DsStoreReader
  def self.read
    self.new(File.open(File.expand_path('~/.Trash/.DS_Store'), 'rb') { |f| f.read })
  end

  attr_reader :files

  def initialize(guts)
    @guts = guts
    @files = []
    @record_inc = 0
    @idx = 0

    @file_id_header = OpenStruct.new(pattern: /#{"\x00\x00\x00[^\x00]"}/)
    @ustr_header = OpenStruct.new(pattern: /ustr/)
    @file_path_type = OpenStruct.new(pattern: /ptbL/, type_char: 'L')
    @file_name_type = OpenStruct.new(pattern: /ptbN/, type_char: 'N')

    @all_headers = [
      @file_id_header,
      @ustr_header,
      @file_path_type,
      @file_name_type
    ]
  end

  # isn't definitive since only grepping on presence of period in filename :|
  def missing_original_dirs
    @files.select { |tf| tf.filename !~ /\./ && !File.exists?(tf.original_path_filename) }
  end

  def missing_original_dir_with_parent_present
    missing_original_dirs.select do |tf|
      File.exists?(tf.parent_dir)
    end
  end

  def parse
    init_index
    i = 0
    last_err_idx = -1
    begin
      loop do
        @files << next_file
        i += 1
        print '.' if i.divmod(100)[1] == 0
      end
    rescue EofError => e
      puts 'Done.'
      return
    rescue => e
      if @idx == last_err_idx
        $stderr.puts 'Last move on attempt failed. Bumping idx by one.'
        fast_forward(1)
        retry
      end

      $stderr.puts [e.message, e.backtrace[0..2]].join("\n")
      $stderr.puts "Error on after file #{i}, record #{@record_inc}, idx #{@idx}"
      $stderr.puts "DUMP @idx-300..@idx-1:\n#{@guts[@idx-300..@idx-1].inspect}"
      $stderr.puts "DUMP @idx..@idx+300:\n#{@guts[@idx..@idx+300].inspect}"
      $stderr.puts '-' * 80

      $stderr.puts 'Attempting to move on...'
      last_err_idx = @idx
      retry
    end
  end

  def init_index
    idx = @guts =~ /#{"\x00\x00\"\x00"}/
    fast_forward_to(idx + 1)
  end

  def next_file
    file = TrashedFile.new

    l_rec = nil
    loop do
      unknown_record = read_record
      case unknown_record[:type]
      when 'L'
        l_rec = unknown_record
        break
      when 'N'
        # not sure why this happens, but best guess is that multiple
        # N records all belong to the same location L record. Most
        # of this analysis appears to support that. Though some of
        # the 'extra' N records are odd. In one case, the file_id
        # and filename were NOT similar (IOW, the file_id wasn't the
        # filename plus some unique data).
        #
        # This whole method should probably be restructured to account
        # for multiples.
        $stderr.puts "Skipping extra 'N' record before idx #{@idx}"
        $stderr.puts "Last file l_rec: #{@files.last.l_rec.inspect}"
        $stderr.puts "Last file n_rec: #{@files.last.n_rec.inspect}"
        $stderr.puts "    Extra n_rec: #{unknown_record}"
        next
      else
        raise "Unexpected '#{unknown_record[:type]} record: #{unknown_record}'"
      end
    end

    n_rec = read_record
    raise "Unexpected L record of type #{l_rec[:type]}" unless l_rec[:type] == 'L'
    raise "Unexpected N record of type #{n_rec[:type]}" unless n_rec[:type] == 'N'
    unless l_rec[:file_id] == n_rec[:file_id]
      dump = [
        "L file_id: #{l_rec[:file_id]}",
        "N file_id: #{n_rec[:file_id]}",
        "L file_id: #{l_rec[:file_id].inspect}",
        "N file_id: #{n_rec[:file_id].inspect}",
      ]
      raise "Unmatched L & N records\n#{dump.join("\n")}"
    end

    file.file_id = l_rec[:file_id].empty? ? n_rec[:data] : l_rec[:file_id]
    file.filename = n_rec[:data]
    file.path = l_rec[:data]

    file.l_rec = l_rec
    file.n_rec = n_rec
    file
  end

  def read_record
    seek_header(@file_id_header)

    file_id = read_string

    header = read_header([@file_path_type, @file_name_type])
    read_header([@ustr_header])

    data = read_string

    {file_id: file_id, data: data, type: header.type_char}.tap do |record|
      @record_inc += 1
    end
  rescue FileIdHeaderInDataError => e
    # there's a good chance there's data I'm just missing that would direct
    # me past this sort of thing, but, for now, just trying to get the bulk
    # of the data here.
    $stderr.puts "Possible garbage at idx #{@idx}, file_id_header within string data."
    $stderr.puts e.message
    fast_forward(1)
    retry
  end

  def read_string
    s = ''

    fast_forward_to(@idx)
    loop do
      r = data_range(4, len: read_length)
      s << r.extract_string

      fast_forward_to(r.dst + 1)

      # saw a case that may be corruption, but didn't act like it,
      # where it appeared to be two file_id_header together and
      # the data should be concatenated

      break # unless peek_header == @file_id_header
    end

    s
  end

  def read_length
    len_range = data_range(0, len: 4)
    (len_range.extract_bytes.unpack('N')[0]) * 2
  end

  def read_header(headers=@all_headers)
    seek_header(headers).tap { fast_forward(4) }
  end

  def seek_header(headers=@all_headers)
    headers=[headers].flatten
    loop do
      header = peek_header
      if headers.include?(header)
        return header
      else
        fast_forward_to(@idx + 1)
      end
    end
  end

  def peek_header
    bytes = data_range(0, len: 4).extract_bytes
    @all_headers.detect { |h| bytes =~ h.pattern }
  end

  def data_range(idx, opts)
    DataRange.new(@guts, @idx, idx, opts)
  end

  def fast_forward(len)
    fast_forward_to(@idx + len)
  end

  def fast_forward_to(idx)
    @idx = idx
    raise EofError, 'EOF' unless @idx <= @guts.length
  end
end

class DataRange
  attr_accessor :src, :dst

  def initialize(s, offset, start, opts)
    @s = s
    @offset = offset
    @src = offset + start
    @dst = offset + (opts[:dst] || (start + opts[:len] - 1))
  end

  def length
    (@dst - @src) + 1
  end

  def extract_bytes
    @s[@src..@dst]
  end

  def extract_string
    try_ascii(extract_bytes)
  end

  def try_ascii(utf_16_string)
    unpacked = utf_16_string.unpack('U*')

    one_byte_option = utf_16_string.length.even? && unpacked.each_slice(2).map(&:first).uniq == [0]
    result = one_byte_option ? unpacked.each_slice(2).map(&:last).map(&:chr).join : utf_16_string

    if result =~ /#{"\x00\x00"}/
      raise FileIdHeaderInDataError, utf_16_string.inspect
    end

    result
  end
end

class EofError < RuntimeError
  # so low-rent
end

class FileIdHeaderInDataError < RuntimeError

end

class Fixnum
  def even?
    self.divmod(2)[1] == 0
  end
end

class TrashedFile
  attr_accessor :file_id, :filename, :path
  attr_accessor :l_rec, :n_rec  # debugging

  def original_path_filename
    File.join('/', @path, @filename)
  end

  def parent_dir
    File.dirname(original_path_filename)
  end

  def trash_path_filename
    File.expand_path("~/.Trash/#{@file_id}")
  end

  def mv_command
    rename = if @file_id != @filename
               restored_name = File.join(parent_dir, @file_id)
               final_name = File.join(parent_dir, @filename)
               "&& mv '#{restored_name}' '#{final_name}'"
             else
               ''
             end
    open = "&& open '#{parent_dir}'"
    "mv '#{trash_path_filename}' '#{parent_dir}' #{rename} #{open}"
  end

  # this will NOT update .DS_Store ...
  def restore(for_realz=false, open_finder=false)
    noop = !for_realz
    FileUtils.makedirs parent_dir, :verbose => true, :noop => noop unless File.exists? parent_dir
    FileUtils.move trash_path_filename, parent_dir, :force => false, :verbose => true, :noop => noop
    if @file_id != @filename
      restored_name = File.join(parent_dir, @file_id)
      final_name = File.join(parent_dir, @filename)
      FileUtils.move restored_name, final_name, :force => false, :verbose => true, :noop => noop
    end
    `open '#{parent_dir}'` unless noop || !open_finder
  rescue => e
    $stderr.puts "*** #{e.message}"
  end
end


if __FILE__ == $0
  reader = DsStoreReader.read
  reader.parse
  File.open('files.txt', 'w') do |f|
    reader.files.each { |file| f.puts file.inspect }
  end
end
