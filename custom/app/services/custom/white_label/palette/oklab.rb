# sRGB <-> OKLCH, after Björn Ottosson's OKLab (https://bottosson.github.io/posts/oklab/).
module Custom::WhiteLabel::Palette::Oklab
  LINEAR_TO_LMS = [
    [0.4122214708, 0.5363325363, 0.0514459929],
    [0.2119034982, 0.6806995451, 0.1073969566],
    [0.0883024619, 0.2817188376, 0.6299787005]
  ].freeze

  LMS_TO_LAB = [
    [0.2104542553, 0.7936177850, -0.0040720468],
    [1.9779984951, -2.4285922050, 0.4505937099],
    [0.0259040371, 0.7827717662, -0.8086757660]
  ].freeze

  LAB_TO_LMS = [
    [1.0, 0.3963377774, 0.2158037573],
    [1.0, -0.1055613458, -0.0638541728],
    [1.0, -0.0894841775, -1.2914855480]
  ].freeze

  LMS_TO_LINEAR = [
    [4.0767416621, -3.3077115913, 0.2309699292],
    [-1.2684380046, 2.6097574011, -0.3413193965],
    [-0.0041960863, -0.7034186147, 1.7076147010]
  ].freeze

  module_function

  def linear(value)
    value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
  end

  def gamma(value)
    value <= 0.0031308 ? value * 12.92 : (1.055 * (value**(1 / 2.4))) - 0.055
  end

  # [0..255, 0..255, 0..255] -> [lightness, chroma, hue in radians]
  def rgb_to_oklch(rgb)
    lms = multiply(LINEAR_TO_LMS, rgb.map { |channel| linear(channel / 255.0) }).map { |v| Math.cbrt(v) }
    lightness, a, b = multiply(LMS_TO_LAB, lms)
    [lightness, Math.hypot(a, b), Math.atan2(b, a) % (2 * Math::PI)]
  end

  def oklch_to_linear(lightness, chroma, hue)
    lms = multiply(LAB_TO_LMS, [lightness, chroma * Math.cos(hue), chroma * Math.sin(hue)]).map { |v| v**3 }
    multiply(LMS_TO_LINEAR, lms)
  end

  def oklch_to_rgb(lightness, chroma, hue)
    oklch_to_linear(lightness, chroma, hue).map { |v| (gamma(v.clamp(0.0, 1.0)) * 255).round }
  end

  def in_gamut?(lightness, chroma, hue)
    oklch_to_linear(lightness, chroma, hue).all? { |v| v.between?(-1e-4, 1 + 1e-4) }
  end

  def multiply(matrix, vector)
    matrix.map { |row| row.zip(vector).sum { |weight, value| weight * value } }
  end
end
