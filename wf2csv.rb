#!/usr/bin/env ruby
require 'rubygems'
require_relative 'statement'

if ARGV.include?('--clean')
  Dir.glob('statements/*.pdf.{csv,txt}').each do |generated_file|
    File.delete(generated_file)
  end
end

Dir.glob("statements/*.pdf").each do |pdf|
  st=Statement.new pdf
  puts "#{pdf}, Date: #{st.statement_end_date}, Start #{st.starting_balance}, End #{st.ending_balance}, #{st.all.size} transactions"
end
