defmodule LeitorWeb.ReaderComponents do
  @moduledoc false
  use LeitorWeb, :html

  attr :face, :string, required: true
  attr :font_size, :integer, required: true
  attr :numbers, :boolean, default: nil
  attr :tab, :string, default: "look"
  attr :preferences, :map, default: %{}

  def appearance(assigns) do
    assigns =
      assigns
      |> assign(:size_form, to_form(%{"size" => assigns.font_size}))
      |> assign(:preferences, LeitorWeb.ReadingPreferences.normalize(assigns.preferences))

    ~H"""
    <.popover
      id="reading-appearance"
      class="reading-appearance"
      label={gettext("Reading appearance")}
      trigger_id="reading-font"
      trigger_class="layer-button reader-font"
      panel_class="reading-appearance-panel"
    >
      <:trigger><.icon name="lucide-thin-type" class="size-[18px]" /></:trigger>
      <span id="reading-appearance-controls" phx-hook="ReadingAppearance" phx-update="ignore" hidden></span>
      <div
        class="appearance-segments appearance-tabs"
        role="tablist"
        aria-label={gettext("Appearance section")}
      >
        <button
          :for={{key, label} <- [{"look", "Look"}, {"text", "Text"}]}
          id={"appearance-tab-#{key}"}
          type="button"
          role="tab"
          data-appearance-tab={key}
          aria-selected={to_string(@tab == key)}
          aria-controls={"appearance-panel-#{key}"}
          tabindex={if @tab == key, do: "0", else: "-1"}
          phx-click="appearance-tab"
          phx-value-tab={key}
        ><span>{t(label)}</span></button>
      </div>
      <div
        id="appearance-panel-look"
        role="tabpanel"
        aria-labelledby="appearance-tab-look"
        hidden={@tab != "look"}
        class="appearance-content"
      >
        <div>
          <p class="appearance-label">{gettext("Theme")}</p>
          <div class="appearance-themes">
            <button
              :for={
                {theme, label} <- [
                  {"auto", "Auto"},
                  {"light", "Paper"},
                  {"sepia", "Sepia"},
                  {"snow", "Snow"},
                  {"dark", "Night"},
                  {"ink", "Ink"}
                ]
              }
              id={"reading-theme-#{theme}"}
              type="button"
              class="appearance-theme"
              data-theme-choice={theme}
              aria-label={
                gettext("Use %{theme} theme",
                  theme: t(if theme == "dark", do: "Dark", else: String.capitalize(theme))
                )
              }
              aria-pressed="false"
              phx-click={JS.dispatch("leitor:set-theme", detail: %{theme: theme})}
            >
              <span class={"appearance-paper appearance-paper-#{theme}"} aria-hidden="true"><span :if={
                theme != "auto"
              }>{gettext("Aa")}</span><span :if={theme == "auto"} class="appearance-auto-light">{gettext(
                "A"
              )}</span><span
                :if={theme == "auto"}
                class="appearance-auto-dark"
              >{gettext("a")}</span></span>
              <span>{t(label)}</span>
            </button>
          </div>
        </div>
        <div class="appearance-row">
          <span>{gettext("Pen")}</span>
          <div class="appearance-pens">
            <button
              :for={
                {pen, label} <- [
                  {"vermilion", "Vermilion"},
                  {"cobalt", "Cobalt"},
                  {"moss", "Moss"},
                  {"graphite", "Graphite"}
                ]
              }
              id={"reading-pen-#{pen}"}
              type="button"
              class={"appearance-pen appearance-pen-#{pen}"}
              aria-label={gettext("%{color} pen", color: t(label))}
              aria-pressed={to_string(@preferences["pen"] == pen)}
              phx-click="reading-option"
              phx-value-key="pen"
              value={pen}
            ><span></span></button>
            <span class="appearance-pen-label">{t(String.capitalize(@preferences["pen"]))}</span>
          </div>
        </div>
        <div :if={!is_nil(@numbers)} class="reading-display-options">
          <button
            id="reading-paragraph-numbers"
            type="button"
            role="switch"
            aria-label={gettext("Paragraph numbers")}
            aria-checked={to_string(@numbers)}
            phx-click="reading-numbers"
          ><.icon name="lucide-pilcrow" class="size-3.5" /> {gettext("Numbers")}</button>
          <button
            :for={
              {key, label, icon} <- [
                {"rail", "Map", "lucide-map"},
                {"focus", "Focus", "lucide-focus"}
              ]
            }
            id={"reading-#{key}"}
            type="button"
            role="switch"
            aria-label={t(label)}
            aria-checked={to_string(@preferences[key])}
            phx-click="reading-option"
            phx-value-key={key}
            value={to_string(!@preferences[key])}
          ><.icon name={icon} class="size-3.5" /> {t(label)}</button>
        </div>
      </div>
      <div
        id="appearance-panel-text"
        role="tabpanel"
        aria-labelledby="appearance-tab-text"
        hidden={@tab != "text"}
        class="appearance-content"
      >
        <div>
          <p class="appearance-label">{gettext("Typeface")}</p>
          <div class="appearance-faces" role="group" aria-label={gettext("Reading font")}>
            <button
              :for={
                {face, label} <- [
                  {"serif", "Serif"},
                  {"book", "Book"},
                  {"sans", "Sans"},
                  {"legible", "Legible"}
                ]
              }
              id={"font-#{face}"}
              type="button"
              class={"appearance-face appearance-face-#{face}"}
              aria-label={
                %{
                  "serif" => "Newsreader",
                  "book" => "Literata",
                  "sans" => "Schibsted",
                  "legible" => "Atkinson Hyperlegible Next"
                }[face]
              }
              aria-pressed={to_string(@face == face)}
              phx-click="reading-face"
              phx-value-face={face}
            ><span aria-hidden="true">{gettext("Ag")}</span><small>{t(label)}</small></button>
          </div>
        </div>
        <.form
          for={@size_form}
          id="reading-size-form"
          phx-change="reading-size"
          class="appearance-row"
        >
          <label for="reading-text-size">{gettext("Size")}</label>
          <div class="appearance-size">
            <button
              id="reading-size-smaller"
              type="button"
              aria-label={gettext("Smaller text")}
              phx-click="reading-size"
              phx-value-size={max(15, @font_size - 1)}
              disabled={@font_size == 15}
            ><.icon name="lucide-minus" class="size-3.5" /></button>
            <.input
              field={@size_form[:size]}
              type="range"
              id="reading-text-size"
              min="15"
              max="28"
              step="1"
              aria-label={gettext("Text size")}
              class="appearance-size-range"
            />
            <button
              id="reading-size-larger"
              type="button"
              aria-label={gettext("Larger text")}
              phx-click="reading-size"
              phx-value-size={min(28, @font_size + 1)}
              disabled={@font_size == 28}
            ><.icon name="lucide-plus" class="size-3.5" /></button>
            <output id="reading-size-value" for="reading-text-size">{@font_size}</output>
          </div>
        </.form>
        <div
          :for={
            {key, label, group, options} <- [
              {"leading", "Spacing", "Line spacing",
               [{"tight", "Snug"}, {"normal", "Even"}, {"loose", "Airy"}]},
              {"width", "Width", "Column width",
               [{"narrow", "Narrow"}, {"normal", "Even"}, {"wide", "Wide"}]},
              {"align", "Align", "Text alignment", [{"left", "Left"}, {"justify", "Justified"}]},
              {"paras", "Paragraphs", "Paragraph style",
               [{"spaced", "Spaced"}, {"indented", "Indented"}]}
            ]
          }
          class="appearance-row"
        >
          <span>{t(label)}</span>
          <div
            class={["appearance-segments", "appearance-segments-#{length(options)}"]}
            role="radiogroup"
            aria-label={t(group)}
          >
            <button
              :for={{value, option_label} <- options}
              id={"reading-#{key}-#{value}"}
              type="button"
              role="radio"
              aria-checked={to_string(@preferences[key] == value)}
              phx-click="reading-option"
              phx-value-key={key}
              value={value}
            ><span><.icon
              :if={key == "align"}
              name={if value == "left", do: "lucide-align-left", else: "lucide-align-justify"}
              class="size-3"
            /> {t(option_label)}</span></button>
          </div>
        </div>
        <button
          :if={
            @face != "serif" || @font_size != 20 ||
              Enum.any?(
                ~w(leading width align paras),
                &(@preferences[&1] != LeitorWeb.ReadingPreferences.defaults()[&1])
              )
          }
          id="reading-text-reset"
          type="button"
          class="appearance-reset"
          phx-click="reading-text-reset"
        ><.icon name="lucide-rotate-ccw" class="size-3" /> {gettext("Reset text settings")}</button>
      </div>
    </.popover>
    """
  end
end
