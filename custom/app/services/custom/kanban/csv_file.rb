require 'csv'

# Reading and writing the CSV files the Kanban imports and exports. Files are UTF-8 (a BOM is
# dropped on reading and added on writing, so a spreadsheet opens accents right), comma or
# semicolon separated (a Brazilian spreadsheet saves with ";").
module Custom::Kanban::CsvFile
  MAX_BYTES = 2.megabytes
  MAX_ROWS = 5000
  BOM = [0xFEFF].pack('U').freeze
  FORMULA_START = /\A[=+\-@\t\r]/

  class Invalid < StandardError
    attr_reader :code, :params

    def initialize(code, params = {})
      @code = code
      @params = params
      super(code.to_s)
    end
  end

  Parsed = Struct.new(:headers, :rows, :delimiter, keyword_init: true)

  # Every row keeps its line number in the file (the header is line 1), so an error can say where.
  def self.parse(text)
    text = readable(text)
    delimiter = detect_delimiter(text)
    lines = numbered_rows(text, delimiter)
    header = lines.shift
    headers = Array(header && header[:cells]).map { |cell| cell.to_s.strip }
    check_shape(headers, lines)
    Parsed.new(headers: headers, delimiter: delimiter, rows: lines)
  rescue CSV::MalformedCSVError
    raise Invalid, :malformed
  end

  # UTF-8 text without its BOM, or Invalid.
  def self.readable(text)
    raise Invalid, :too_big if text.bytesize > MAX_BYTES

    text = text.dup.force_encoding(Encoding::UTF_8)
    raise Invalid, :encoding unless text.valid_encoding?

    text.delete_prefix(BOM)
  end

  def self.check_shape(headers, lines)
    raise Invalid, :empty if headers.compact_blank.empty?
    raise Invalid, :no_rows if lines.empty?
    raise Invalid.new(:too_many_rows, max: MAX_ROWS) if lines.size > MAX_ROWS
  end

  # Blank lines are dropped but still counted, so a row's line number is where it is in the file.
  def self.numbered_rows(text, delimiter)
    reader = CSV.new(text, col_sep: delimiter)
    previous_end = 0
    reader.each_with_object([]) do |cells, rows|
      first_line = previous_end + 1
      previous_end = reader.lineno
      rows << { line: first_line, cells: cells } unless cells.compact.all? { |cell| cell.to_s.strip.empty? }
    end
  end

  def self.detect_delimiter(text)
    first_line = text.lines.first.to_s
    first_line.count(';') > first_line.count(',') ? ';' : ','
  end

  # A cell that starts with = + - @ is read as a formula by a spreadsheet, which can run
  # commands or leak data; a leading apostrophe makes it plain text.
  def self.safe_cell(value)
    text = value.to_s
    text.match?(FORMULA_START) ? "'#{text}" : text
  end

  def self.generate(headers, rows)
    BOM + CSV.generate do |csv|
      csv << headers
      rows.each { |row| csv << row.map { |cell| safe_cell(cell) } }
    end
  end
end
