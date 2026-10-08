defmodule LeitorWeb.ReviewLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Learning

  @impl true
  def mount(_, _, socket),
    do:
      {:ok,
       socket
       |> assign(
         page_title: "Review",
         card: Learning.next_review(socket.assigns.current_scope),
         revealed: false,
         reviewed: 0
       )
       |> stream(:errors, Learning.progress(socket.assigns.current_scope).errors)}

  @impl true
  def handle_event("reveal", _, socket), do: {:noreply, assign(socket, revealed: true)}

  def handle_event("rate", %{"rating" => rating}, socket) when rating in ["again", "hard", "good", "easy"] do
    if socket.assigns.card && socket.assigns.revealed do
      {:ok, _} = Learning.rate(socket.assigns.current_scope, socket.assigns.card.id, rating)

      {:noreply,
       assign(socket,
         card: Learning.next_review(socket.assigns.current_scope),
         revealed: false,
         reviewed: socket.assigns.reviewed + 1
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active="review">
      <StudyComponents.page_heading
        eyebrow="A little repetition goes a long way"
        title="Review"
        subtitle={"#{@reviewed} reviewed today in this session. A word at a time."}
      />
      <div class="review-layout">
        <section>
          <%= if @card do %>
            <section id="review-card" class="review-card">
              <div class="row between">
                <StudyComponents.chip category={@card.category}>
                  {if @card.category == "error", do: "From your writing", else: @card.category}
                </StudyComponents.chip><span class="muted text-xs">Remember before you reveal</span>
              </div>
              <p class="review-context">
                {String.replace(@card.context, ~r/#{Regex.escape(@card.term)}/i, "______")}
              </p>
              <p class="eyebrow">Hint</p><p class="muted">{@card.meaning}</p>
              <%= if @revealed do %>
                <h2 id="review-answer" class="mt-6">{@card.term}</h2>
                <div class="rating-grid">
                  <button
                    :for={
                      {rating, label, interval} <- [
                        {"again", "Again", "1 minute"},
                        {"hard", "Hard", "8 minutes"},
                        {"good", "Good", "At least 1 day"},
                        {"easy", "Easy", "At least 4 days"}
                      ]
                    }
                    id={"rate-#{rating}"}
                    type="button"
                    class="rating"
                    phx-click="rate"
                    phx-value-rating={rating}
                  >{label}<small>{interval}</small></button>
                </div>
              <% else %>
                <button
                  id="reveal-answer"
                  type="button"
                  class="action action-primary mt-8"
                  phx-click="reveal"
                >Show word <.icon name="hero-eye" class="size-4" /></button>
              <% end %>
            </section>
          <% else %>
            <StudyComponents.empty_state
              title={if @reviewed > 0, do: "A little more remembered.", else: "You're all caught up."}
              body="Words return when they're due. Keep reading and collect the ones you'd like to remember."
            >
              <.link navigate={~p"/read"} class="action action-primary">Back to reading →</.link>
            </StudyComponents.empty_state>
          <% end %>
        </section>
        <aside class="stack" aria-label="Recent corrections">
          <h2>Your recent corrections</h2>
          <div id="review-errors" phx-update="stream" class="stack">
            <p id="review-errors-empty" class="hidden only:block muted">
              Corrections saved from writing appear here.
            </p>
            <article :for={{id, error} <- @streams.errors} id={id} class="card stack">
              <strong>{error.term}</strong><p class="muted">{error.meaning}</p>
            </article>
          </div>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
