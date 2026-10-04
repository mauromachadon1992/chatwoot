# Turns one brand colour into the dashboard's accent ramp, so a white-labelled account wears
# its colour everywhere Chatwoot uses blue: primary buttons, links, focus rings, selection
# washes, badges.
#
# Chatwoot's accent is Radix's 12-step blue scale (`--blue-1..12`, light and dark), and
# `n-brand` reads step 9. Rather than invent a new ramp, this one re-hues Chatwoot's own: each
# step keeps the lightness of the blue it replaces, so every contrast relationship the
# dashboard was designed around survives, and takes the brand's hue, with chroma scaled to the
# brand's (never above the original, so tints stay as quiet as Chatwoot's). The work happens in
# OKLCH, where lightness is perceptual and a hue change does not shift it.
#
# Contrast is guaranteed, not hoped for:
# - step 9 (solid fills under white text) reaches 4.5:1 against white, darkening the brand if
#   it has to, and in the dark theme also 3:1 against the page so a focus ring stays visible;
# - step 11 (accent text) reaches 4.5:1, and step 12 7:1, against the step-3 wash they sit on.
class Custom::WhiteLabel::Palette
  # Chatwoot's blue, from app/javascript/dashboard/assets/scss/_next-colors.scss.
  REFERENCE = {
    light: [
      [251, 253, 255], [245, 249, 255], [233, 243, 255], [218, 236, 255], [201, 226, 255], [181, 213, 255],
      [155, 195, 252], [117, 171, 247], [39, 129, 246], [16, 115, 233], [8, 109, 224], [11, 50, 101]
    ],
    dark: [
      [10, 17, 28], [15, 24, 38], [15, 39, 72], [10, 49, 99], [18, 61, 117], [29, 84, 134],
      [40, 89, 156], [48, 106, 186], [39, 129, 246], [21, 116, 231], [126, 182, 255], [205, 227, 255]
    ]
  }.freeze

  # The other blue-derived variables of the same file, re-hued the same way.
  REFERENCE_EXTRAS = {
    light: {
      '--solid-blue' => [218, 236, 255], '--solid-blue-2' => [251, 253, 255],
      '--border-blue-strong' => [18, 61, 117], '--text-blue' => [1, 22, 44]
    },
    dark: { '--solid-blue' => [15, 57, 102], '--border-blue-strong' => [201, 226, 255], '--text-blue' => [213, 234, 255] }
  }.freeze

  # The page each theme's accent has to stand out from (`--background-color`).
  PAGE = { light: [247, 247, 247], dark: [28, 29, 32] }.freeze
  WHITE = [255, 255, 255].freeze

  TEXT_ON_FILL = 4.5   # WCAG AA, normal text
  UI_ON_PAGE = 3.0     # WCAG 1.4.11, non-text contrast
  ACCENT_TEXT = 4.5
  STRONG_TEXT = 7.0
  STEP = 0.005

  attr_reader :brand

  def initialize(hex)
    @brand = Color.from_hex(hex)
  end

  # The colour actually used for solid fills (light theme): the brand, or the closest darker
  # shade of it that keeps white text readable. The browser chrome uses it too.
  def action_hex
    themes[:light][:steps][8].hex
  end

  def adjusted?
    !action_hex.casecmp?(brand.hex)
  end

  # { light: { '--blue-1' => '251 253 255', ... }, dark: { ... } }
  def variables
    themes.transform_values do |theme|
      vars = theme[:steps].each_with_index.to_h { |color, index| ["--blue-#{index + 1}", color.channels] }
      vars.merge!(theme[:extras].transform_values(&:channels))
      vars['--border-blue'] = "#{theme[:steps][8].rgb.join(', ')}, 0.5"
      vars
    end
  end

  # Unlayered, so it wins over Chatwoot's `@layer base` tokens; the dashboard toggles the dark
  # theme with a class on <body>, which is where the dark values have to land.
  def to_css
    light, dark = variables.values_at(:light, :dark)
    ":root{#{declarations(light)}}body.dark{#{declarations(dark)}}"
  end

  private

  def themes
    @themes ||= %i[light dark].index_with { |theme| build(theme) }
  end

  def build(theme)
    reference = REFERENCE[theme].map { |rgb| Color.from_rgb(rgb) }
    ratio = chroma_ratio(reference[8])
    steps = reference.map { |color| rehue(color, ratio) }
    apply_accent_steps(steps, reference, theme)

    { steps: steps, extras: REFERENCE_EXTRAS[theme].transform_values { |rgb| rehue(Color.from_rgb(rgb), ratio) } }
  end

  # Steps 9 to 12 carry text and fills, so they follow the contrast rules rather than the
  # reference lightness alone. Step 10 (hover) keeps its distance from step 9.
  def apply_accent_steps(steps, reference, theme)
    toward = theme == :light ? -STEP : STEP
    steps[8] = action(theme)
    steps[9] = shift(steps[8], reference[9].l - reference[8].l, reference[9].c / reference[8].c)
    steps[10] = ensure_contrast(steps[10], steps[2], ACCENT_TEXT, toward)
    steps[11] = ensure_contrast(steps[11], steps[2], STRONG_TEXT, toward)
  end

  # How saturated the brand is next to Chatwoot's blue. Capped at 1 so backgrounds never get
  # louder than the original; a grey brand gets grey tints.
  def chroma_ratio(reference_nine)
    (brand.c / reference_nine.c).clamp(0.0, 1.0)
  end

  def rehue(color, ratio)
    Color.from_oklch(color.l, color.c * ratio, brand.h)
  end

  def shift(color, delta_l, chroma_factor = 1)
    Color.from_oklch(color.l + delta_l, color.c * chroma_factor, color.h)
  end

  # Step 9: dark enough for white text; in the dark theme, also light enough to see on the page.
  def action(theme)
    color = brand
    color = shift(color, -STEP) while color.contrast(white) < TEXT_ON_FILL && color.l > STEP
    return color unless theme == :dark

    page = Color.from_rgb(PAGE[:dark])
    while color.contrast(page) < UI_ON_PAGE
      lighter = shift(color, STEP)
      break if lighter.contrast(white) < TEXT_ON_FILL

      color = lighter
    end
    color
  end

  def ensure_contrast(color, against, minimum, delta)
    color = shift(color, delta) while color.contrast(against) < minimum && color.l.between?(STEP, 1 - STEP)
    color
  end

  def white
    @white ||= Color.from_rgb(WHITE)
  end

  def declarations(vars)
    vars.map { |name, value| "#{name}:#{value};" }.join
  end
end
