require_relative 'pdf_parser'
require 'csv'

class Statement
  attr_accessor :statement_end_date, :account_number, :ending_balance, :starting_balance, :total_deposits, :total_withdrawals, :deposits, :withdrawals,:content
  
  MONTHS="(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)"
  DAY="[0123]\\d"
  DATE="(#{MONTHS}\s+#{DAY})"
  AMOUNT="((- )?(\\d{1,3},)?\\d{1,3}\\.\\d{2}) "
  
#  AMOUNT="\s{5}((- )?[0123456789,]+\.[0123456789]{2})"
  
  def initialize(file_name)
    @content=PdfParser.new(file_name).content
    year_part = statement_end_date.split(/\//).last
    @year = year_part.length == 4 ? year_part : "20" + year_part
    CSV.open("#{file_name}.csv", 'w') do |csv|
      all.each do |x|
        csv << [x[0], payee_from_description(x[1]), x[1], x[2]]
      end
    end
    unless audit?
      puts "AUDIT file #{file_name}" 
      [:statement_end_date, :account_number, :starting_balance,:ending_balance, :calculated_ending_balance,  :total_deposits, :calculated_total_deposits, :total_withdrawals, :calculated_total_withdrawals].each do |field|
        puts "#{field.to_s}=#{self.send(field)}"
      end
      puts "#{calculated_ending_balance-ending_balance} missing"
    end
  end
  
  def statement_end_date
    @statement_end_date ||= begin
      value = find_value(/Statement End Date:\s*(\d\d\/\d\d\/\d\d)/)
      value = find_value(/Statement Closing Date\s*(\d\d\/\d\d\/\d\d)/) if value.nil?
      value = find_value(/Statement Period\s+\d\d\/\d\d\/\d{4}\s+to\s+(\d\d\/\d\d\/\d{4})/) if value.nil?
      value ? value[0] : nil
    end
  end

  def starting_balance
    @starting_balance ||= begin
      legacy = find_value(/#{DATE} BEGINNING BALANCE\s*#{AMOUNT}/)
      if legacy
        to_number(legacy[2])
      else
        current = find_value(/Previous Balance\s*\$((?:\d{1,3},)*\d+\.\d{2})/)
        current ? to_number(current[0]) : 0.0
      end
    end
  end

  def ending_balance
    @ending_balance ||= begin
      legacy = find_value(/#{DATE} ENDING BALANCE\s*#{AMOUNT}/)
      if legacy
        to_number(legacy[2])
      else
        current = find_value(/New Balance\s*(?:=\s*)?\$((?:\d{1,3},)*\d+\.\d{2})/)
        current ? to_number(current[0]) : 0.0
      end
    end
  end

  def account_number
    @account_number ||= begin
      legacy = find_value(/Account Number:\s*(\d+-?\d+)/)
      if legacy
        legacy[0]
      else
        current = find_value(/Account Number\s*((?:\d{4}\s+){3}\d{4})/)
        current ? current[0].gsub(/\s+/, '') : nil
      end
    end
  end
  
  def total_deposits
    @total_deposits ||= begin
      legacy = find_value(/TOTAL DEPOSITS\/CREDITS\s*#{AMOUNT}/)
      if legacy
        to_number(legacy[0])
      else
        calculate_balance(deposits)
      end
    end
  end
  
  def total_withdrawals
    @total_withdrawals ||= begin
      legacy = find_value(/TOTAL WITHDRAWALS\/DEBITS\s*#{AMOUNT}/)
      if legacy
        to_number(legacy[0])
      else
        calculate_balance(withdrawals)
      end
    end
  end
  
  
  def calculated_total_deposits
    calculate_balance(deposits)
  end
  
  def calculated_total_withdrawals
    calculate_balance(withdrawals)
  end
  
  def turnover
    calculated_total_deposits+calculated_total_withdrawals
  end
  
  def calculated_ending_balance
     truncate(starting_balance+turnover)
  end
  
  def audit?
    calculated_ending_balance===ending_balance
  end

  def calculate_balance(txns)
    balance=txns.inject(0) do |balance,txn|
      balance+=txn[2]
      balance
    end
    truncate(balance)
  end
  
  def deposits
    @deposits ||= begin
      if legacy_format?
        transactions(deposits_section)
      else
        transactions_from_details.select { |x| x[:credit] && x[:credit] > 0 }.collect do |x|
          [format_date(x[:post_date]), x[:description], x[:credit]]
        end
      end
    end
  end
  
  def withdrawals
    @withdrawals ||= begin
      if legacy_format?
        transactions(withdrawals_section)+checks
      else
        transactions_from_details.select { |x| x[:charge] && x[:charge] > 0 }.collect do |x|
          [format_date(x[:post_date]), x[:description], -x[:charge]]
        end
      end
    end
  end
  
  def checks
    if has_checks?
      transactions(checks_section).collect{|x|[x[0],x[1],-x[2]]}
    else
      []
    end
  end
  
  def all
    (deposits+withdrawals)
  end
  
  def transactions(text)
    text.scan(/#{DATE} (.*?) #{AMOUNT}/).collect do |x|
      [ format_date(x[0]), 
        x[2] ? x[2].strip.gsub(/,/,' ').gsub(/\s+/,' ') : 'In branch check',to_number(x[3])]
    end
  end
  
  def deposits_section
    @content[deposits_start,withdrawals_start-deposits_start]
  end

  def withdrawals_section
    if has_checks?
      @content[withdrawals_start,checks_start-withdrawals_start]
    else
      @content[withdrawals_start,daily_balance_summary_start-withdrawals_start]
    end
  end

  def checks_section
    @content[checks_start,daily_balance_summary_start-checks_start]
  end
  
  def has_checks?
    checks_start!=nil
  end
  
  def deposits_start
    @content.index "DEPOSITS AND CREDITS"
  end

  def withdrawals_start
    @content.index "WITHDRAWALS AND DEBITS"
  end

  def checks_start
    @content.index "CHECKS PAID"
  end
  
  def daily_balance_summary_start
    @content.index "DAILY BALANCE SUMMARY"
  end
  
  def to_number(amount)
    truncate(amount.gsub(/[ ,]/,'').to_f)
  end
  
  def truncate(number)
    ((((number*100).round).to_f)/100).to_f
  end
  
  def format_date(d)
    if d =~ /\A\d\d\/\d\d\z/
      month, day = d.split('/')
      [month, day, @year].join('-')
    else
      (d.split + [@year]).join('-')
    end
  end
  
  def to_hash
    attributes={}
    [:statement_end_date, :account_number, :ending_balance, :starting_balance, :total_deposits, :total_withdrawals, :deposits, :withdrawals].each do |name|
      attributes[name]=self.send(name)
    end
    attributes
  end
#  protected
  
  def search(regex)
    @content.scan(regex)
  end
  
  def find_value(regex)
    search(regex).first
  end

  def legacy_format?
    !!find_value(/Statement End Date:\s*(\d\d\/\d\d\/\d\d)/)
  end

  def transaction_details_section
    @transaction_details_section ||= begin
      start = @content.index("Transaction Details") || @content.index("Transactions")
      return "" if start.nil?

      stop = @content.index("TOTAL *FINANCE CHARGE*", start) ||
             @content.index("Interest Charge Calculation", start) ||
             @content.length
      @content[start, stop - start]
    end
  end

  def transactions_from_details
    @transactions_from_details ||= begin
      rows = []
      transaction_details_section.each_line do |line|
        finance_match = line.match(/^\s*PERIODIC \*FINANCE CHARGE\*\s+PURCHASES\s+\$((?:\d{1,3},)*\d+\.\d{2})\s+CASH ADVANCE\s+\$((?:\d{1,3},)*\d+\.\d{2})\s+((?:\d{1,3},)*\d+\.\d{2})\s*$/)
        unless finance_match.nil?
          statement_month_day = statement_end_date[0, 5]
          description = "PERIODIC *FINANCE CHARGE* PURCHASES $#{finance_match[1]} CASH ADVANCE $#{finance_match[2]}"
          rows << { post_date: statement_month_day, description: description, credit: nil, charge: to_number(finance_match[3]) }
          next
        end

        # Current WF layout: [card last 4 (optional)] trans date, post date, reference id, description, credits(optional), charges(optional)
        match = line.match(/^\s*(?:\d{4}\s+)?(\d\d\/\d\d)\s+(\d\d\/\d\d)\s+\S+\s+(.*?)\s{2,}((?:(?:\d{1,3},)*\d+\.\d{2})(?:\s+(?:\d{1,3},)*\d+\.\d{2})?)\s*$/)
        next if match.nil?

        description = match[3].gsub(/\s+/, ' ').strip
        amounts = match[4].scan(/(?:\d{1,3},)*\d+\.\d{2}/)
        credit = nil
        charge = nil
        if amounts.size == 2
          credit = to_number(amounts[0])
          charge = to_number(amounts[1])
        elsif amounts.size == 1
          value = to_number(amounts[0])
          if credit_like_description?(description)
            credit = value
          else
            charge = value
          end
        end

        rows << { post_date: match[2], description: description, credit: credit, charge: charge }
      end
      rows
    end
  end

  def credit_like_description?(description)
    description =~ /(PAYMENT|CREDIT|REFUND|REVERSAL|THANK YOU)/i
  end

  def payee_from_description(description)
    normalized = description.to_s.strip
    return '' if normalized.empty?

    first_token = normalized.split(/\s+/).first
    payee = first_token[/\A[0-9A-Za-z]+/]
    return payee unless payee.nil? || payee.empty?

    normalized[/[0-9A-Za-z]+/] || ''
  end
end