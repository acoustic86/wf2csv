require 'pdf/reader'

class PdfParser
  
  attr_accessor :content

  def initialize(file)
    reader = PDF::Reader.new(file)
    @content = reader.pages.map(&:text).join("\n")
  end
end
