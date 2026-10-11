# What every CSV importer shares: guessing which column is which field from the header, and the
# shape of a row's verdict. A subclass says its FIELDS and how to `analyze` a row (read only,
# so the dry run writes nothing) and `apply` it (the real run).
class Custom::Kanban::Importers::Base
  # `action` is :create, :update or :skip; `messages` is empty for a row that can be imported.
  Verdict = Struct.new(:action, :attrs, :messages, keyword_init: true) do
    def error?
      messages.any?
    end
  end

  # Field => header names (as `normalize_header` writes them) that mean it.
  def self.aliases
    raise NotImplementedError
  end

  # The fields that must be mapped for the file to be importable.
  def self.required_fields
    []
  end

  def self.normalize_header(header)
    I18n.transliterate(header.to_s).downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_|_\z/, '')
  end

  # { field => header } for the columns whose name is recognised; each header is used once.
  def self.auto_mapping(headers)
    taken = []
    aliases.each_with_object({}) do |(field, names), mapping|
      header = headers.find { |candidate| taken.exclude?(candidate) && names.include?(normalize_header(candidate)) }
      next unless header

      mapping[field.to_s] = header
      taken << header
    end
  end

  def initialize(import)
    @import = import
    @account = import.account
    @seen = {}
  end

  # The cells of a row as { field => stripped text or nil }.
  def values(cells, headers, mapping)
    mapping.each_with_object({}) do |(field, header), values|
      index = headers.index(header)
      values[field.to_sym] = index && cells[index].to_s.strip.presence
    end
  end

  def t(key, **)
    I18n.t("flow_kanban.imports.errors.#{key}", **)
  end

  # Remembers a row's identity; a second row with the same one is a repeat.
  def repeat?(key)
    return true if @seen.key?(key)

    @seen[key] = true
    false
  end

  def invalid(*messages)
    Verdict.new(action: :skip, attrs: {}, messages: messages.flatten)
  end
end
