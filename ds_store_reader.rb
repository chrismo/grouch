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
    @guts       = guts
    @files      = []
    @record_inc = 0
    @idx        = 0

    @file_id_header = OpenStruct.new(pattern: /#{"\x00\x00\x00[^\x00]"}/)
    @ustr_header    = OpenStruct.new(pattern: /ustr/)
    @file_path_type = OpenStruct.new(pattern: /ptbL/, type_char: 'L')
    @file_name_type = OpenStruct.new(pattern: /ptbN/, type_char: 'N')

    @all_headers = [
      @file_id_header,
      @ustr_header,
      @file_path_type,
      @file_name_type
    ]
  end

  def parse
    init_index
    i            = 0
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

  class TrashedFile
    attr_accessor :file_id, :filename, :path
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
        # not sure how often this happens yet
        puts "Skipping extraneous 'N' record: #{unknown_record}"
        next
      else
        raise "Unexpected '#{unknown_record[:type]} record: #{unknown_record}'"
      end
    end

    n_rec = read_record
    raise 'Unexpected L record' unless l_rec[:type] == 'L'
    raise 'Unexpected N record' unless n_rec[:type] == 'N'
    unless l_rec[:file_id] == n_rec[:file_id]
      dump = [
        "L file_id: #{l_rec[:file_id]}",
        "N file_id: #{n_rec[:file_id]}",
        "L file_id: #{l_rec[:file_id].inspect}",
        "N file_id: #{n_rec[:file_id].inspect}",
      ]
      raise "Unmatched L & N records\n#{dump.join("\n")}"
    end

    file.file_id  = l_rec[:file_id].empty? ? n_rec[:data] : l_rec[:file_id]
    file.filename = n_rec[:data]
    file.path     = l_rec[:data]
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
  end

  def read_string(idx=@idx)
    s = ''

    fast_forward_to(idx)
    loop do
      r = data_range(4, len: read_length)
      s << r.extract_from

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
    (len_range.extract_bytes_from.unpack('N')[0]) * 2
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
    bytes = data_range(0, len: 4).extract_bytes_from
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
    @s      = s
    @offset = offset
    @src    = offset + start
    @dst    = offset + (opts[:dst] || (start + opts[:len] - 1))
  end

  def length
    (@dst - @src) + 1
  end

  def extract_bytes_from
    @s[@src..@dst]
  end

  def extract_from
    try_ascii(extract_bytes_from)
  end

  def try_ascii(utf_16_string)
    unpacked = utf_16_string.unpack('U*')

    one_byte_option = utf_16_string.length.even? && unpacked.each_slice(2).map(&:first).uniq == [0]
    one_byte_option ? unpacked.each_slice(2).map(&:last).map(&:chr).join : utf_16_string
  rescue => e
    puts utf_16_string.inspect
    raise e
  end
end

class EofError < RuntimeError
  # so low-rent
end

class CorruptionError < RuntimeError
  attr_reader :index_to_pick_up_at

  def initialize(message, index_to_pick_up_at)
    super(message)
    @index_to_pick_up_at = index_to_pick_up_at
  end
end


class Fixnum
  def even?
    self.divmod(2)[1] == 0
  end
end

if __FILE__ == $0
  reader = DsStoreReader.read
  reader.parse
  File.open('files.txt', 'w') do |f|
    reader.files.each { |file| f.puts file.inspect }
  end
end
