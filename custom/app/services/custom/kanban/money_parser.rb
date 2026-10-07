# Reads an amount a person typed in a spreadsheet ("1.234,56", "1234.56", "R$ 10", "1,5") into
# minor units, or nil when it is not an amount. Comma and dot are told apart by position: when
# both appear the last one is the decimal mark; a single kind repeated, or one followed by exactly
# three digits, is a thousands separator ("1.234", "1,234,567"); otherwise it is the decimal mark.
module Custom::Kanban::MoneyParser
  THOUSANDS = /\A\d{1,3}([.,]\d{3})+\z/
  GROUPED = /\A(\d+|\d{1,3}([.,]\d{3})+)\z/

  def self.cents(text)
    return nil if text.to_s.strip.start_with?('-')

    # Only a currency symbol and spaces may surround the digits: "12abc" or "P-1" is not an amount.
    cleaned = text.to_s.gsub(/R\$|US\$|[$€£]|\s| /i, '')
    return nil unless cleaned.match?(/\A[\d.,]+\z/)

    whole, fraction = split(cleaned)
    return nil unless whole && fraction.match?(/\A\d{0,2}\z/) && whole.match?(/\A\d+\z/)

    (whole.to_i * 100) + fraction.ljust(2, '0').to_i
  end

  def self.decimal(cents)
    format('%<whole>d.%<fraction>02d', whole: cents / 100, fraction: cents % 100)
  end

  # [whole digits, fraction digits], or nil when the marks do not make sense.
  def self.split(cleaned)
    marks = cleaned.scan(/[.,]/)
    return [cleaned, ''] if marks.empty?

    last = cleaned.rindex(/[.,]/)
    after = cleaned[(last + 1)..]
    return thousands_only(cleaned) if marks.uniq.one? && (marks.size > 1 || after.length == 3)

    before = cleaned[0...last]
    return nil unless before.match?(GROUPED) && before.scan(/[.,]/).none?(cleaned[last])

    [before.delete('.,'), after]
  end

  def self.thousands_only(cleaned)
    cleaned.match?(THOUSANDS) ? [cleaned.delete('.,'), ''] : nil
  end
end
