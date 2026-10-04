# An sRGB colour with its OKLCH coordinates, and its WCAG contrast against another colour.
# Out-of-gamut OKLCH values are brought back by reducing chroma at the same lightness and hue,
# the CSS Color 4 approach.
class Custom::WhiteLabel::Palette::Color
  Oklab = Custom::WhiteLabel::Palette::Oklab

  attr_reader :rgb, :l, :c, :h

  def self.from_hex(hex)
    from_rgb(hex.to_s.delete_prefix('#').scan(/../).map { |pair| pair.to_i(16) })
  end

  def self.from_rgb(rgb)
    new(rgb, *Oklab.rgb_to_oklch(rgb))
  end

  def self.from_oklch(lightness, chroma, hue)
    lightness = lightness.clamp(0.0, 1.0)
    chroma = gamut_chroma(lightness, [chroma, 0.0].max, hue)
    new(Oklab.oklch_to_rgb(lightness, chroma, hue), lightness, chroma, hue)
  end

  # The largest chroma, up to the one asked for, that sRGB can show at this lightness and hue.
  def self.gamut_chroma(lightness, chroma, hue)
    return chroma if Oklab.in_gamut?(lightness, chroma, hue)

    low = 0.0
    high = chroma
    12.times do
      mid = (low + high) / 2
      Oklab.in_gamut?(lightness, mid, hue) ? low = mid : high = mid
    end
    low
  end

  def initialize(rgb, lightness, chroma, hue)
    @rgb = rgb
    @l = lightness
    @c = chroma
    @h = hue
  end

  def hex
    "##{rgb.map { |channel| format('%02X', channel) }.join}"
  end

  def channels
    rgb.join(' ')
  end

  def luminance
    @luminance ||= begin
      r, g, b = rgb.map { |channel| Oklab.linear(channel / 255.0) }
      (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
    end
  end

  def contrast(other)
    other = self.class.from_rgb(other) if other.is_a?(Array)
    low, high = [luminance, other.luminance].minmax
    (high + 0.05) / (low + 0.05)
  end
end
