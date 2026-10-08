defmodule LeitorWeb.ComponentGalleryLive do
  @moduledoc false
  use LeitorWeb, :live_view

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: "Components", dialog?: false, form: to_form(%{}, as: :sample))}

  @impl true
  def handle_event("dialog", _, socket), do: {:noreply, assign(socket, dialog?: !socket.assigns.dialog?)}
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <StudyComponents.page_heading
        title="A shared visual language."
        subtitle="Reusable function components, real controls, and accessible states."
        eyebrow="Development · components"
      />
      <div class="two-column">
        <section class="card stack">
          <h2>Actions & categories</h2><div class="row wrap">
            <.button>Primary action</.button><button class="action">Secondary action</button><.button disabled>Disabled</.button><button
              class="icon-button"
              aria-label="Listen"
            ><.icon name="hero-speaker-wave" class="size-5" /></button>
          </div>
          <div class="row wrap">
            <StudyComponents.chip
              :for={category <- ["verb", "noun", "adj", "adv", "pron", "prep", "conj", "word"]}
              category={category}
            >
              {category}
            </StudyComponents.chip>
          </div>
          <StudyComponents.progress value={3} max={5} label="Sample progress" />
          <button
            id="open-gallery-dialog"
            class="action"
            phx-click={JS.push_focus() |> JS.push("dialog")}
          >Open accessible dialog</button>
        </section>
        <section class="card stack">
          <h2>Form fields</h2><.form for={@form} id="gallery-form">
            <.input field={@form[:email]} type="email" label="Email" placeholder="you@example.com" /><.input
              field={@form[:notes]}
              type="textarea"
              label="Notes"
            /><.input
              field={@form[:category]}
              type="select"
              label="Category"
              options={["Word", "Expression"]}
            /><.input field={@form[:known]} type="checkbox" label="I know this word" />
          </.form>
        </section>
        <StudyComponents.stat
          label="Words collected"
          value={128}
          detail="Illustrative component data"
        />
        <StudyComponents.empty_state
          title="A fresh beginning."
          body="An empty state should explain the next useful action."
        >
          <.link navigate={~p"/read"} class="action">Read a sentence</.link>
        </StudyComponents.empty_state>
      </div>
      <StudyComponents.dialog
        :if={@dialog?}
        id="gallery-dialog"
        title="A little room to focus"
        on_close={JS.push("dialog")}
      >
        <p>Tab stays inside this dialog. Escape closes it.</p><button
          class="action"
          phx-click="dialog"
        >Done</button>
      </StudyComponents.dialog>
    </Layouts.app>
    """
  end
end
