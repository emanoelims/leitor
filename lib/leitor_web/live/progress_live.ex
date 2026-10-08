defmodule LeitorWeb.ProgressLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Learning

  @impl true
  def mount(_params, _session, socket) do
    progress = Learning.progress(socket.assigns.current_scope)

    {:ok,
     socket |> assign(page_title: "Progress", progress: progress, period: "month") |> stream(:errors, progress.errors)}
  end

  @impl true
  def handle_event("period", %{"period" => period}, socket) when period in ["week", "month"],
    do: {:noreply, assign(socket, period: period)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active="progress"
      class="page progress-page"
      context_detail={if @period == "week", do: "Last 7 days", else: "Last 5 weeks"}
    >
      <:header_controls>
        <div class="row" role="group" aria-label="Activity period">
          <button
            class={["layer-button", @period == "week" && "active"]}
            phx-click="period"
            phx-value-period="week"
            aria-pressed={@period == "week"}
          >7d</button><button
            class={["layer-button", @period == "month" && "active"]}
            phx-click="period"
            phx-value-period="month"
            aria-pressed={@period == "month"}
          ><.icon name="hero-calendar-days" class="size-[18px]" />Month</button>
        </div>
      </:header_controls>
      <h1 class="sr-only">Progress · Small steps add up</h1>
      <div class="progress-panels">
        <section class="card stack" aria-label="Study streak">
          <div class="row between">
            <div>
              <p class="eyebrow">Current streak</p><p class="progress-number">
                <.icon name="hero-fire" class="size-8 text-[#c2552b]" />{@progress.streak}{if @progress.streak ==
                                                                                                35,
                                                                                              do: "+",
                                                                                              else: ""} {if @progress.streak ==
                                                                                                              1,
                                                                                                            do:
                                                                                                              "day",
                                                                                                            else:
                                                                                                              "days"}
              </p>
            </div><span class="muted text-sm">Daily activity · UTC</span>
          </div>
          <div class="activity-grid" role="list" aria-label="Daily practice activity">
            <div
              :for={
                day <- if(@period == "week", do: Enum.take(@progress.days, -7), else: @progress.days)
              }
              role="listitem"
              tabindex="0"
              title={"#{day.date}: #{day.count} activities"}
              aria-label={"#{day.date}: #{day.count} activities"}
              class={["activity-day", day.count > 0 && "active"]}
              data-level={min(day.count, 4)}
            >
              <span class="sr-only">{day.date}: {day.count}</span>
            </div>
          </div>
          <div class="row wrap activity-key">
            <span><i></i>No practice</span><span><i class="active"></i>1 activity</span><span><i class="more"></i>2+ activities</span>
          </div>
        </section>
        <section class="card stack" aria-label="Known words">
          <p class="eyebrow">Words you know</p><p class="progress-number">{@progress.known}</p>
          <div
            class="vocabulary-chart"
            role="list"
            aria-label="Currently known words collected by week"
          >
            <div
              :for={week <- @progress.weekly_known}
              role="listitem"
              aria-label={"Week of #{week.date}: #{week.count} known words"}
              tabindex="0"
              title={"Week of #{week.date}: #{week.count} known words"}
            >
              <span style={"height: #{max(3, round(week.count * 100 / max(Enum.max_by(@progress.weekly_known, & &1.count).count, 1)))}%"}></span><small>{Calendar.strftime(
                week.date,
                "%d %b"
              )}</small>
            </div>
          </div>
          <p class="muted text-xs">Currently known words, grouped by the week you collected them.</p>
        </section>
        <section class="card stack" aria-label="Writing corrections">
          <p class="eyebrow">Mistakes become practice</p><div
            id="progress-errors"
            phx-update="stream"
            class="stack"
          >
            <p id="no-errors" class="hidden only:block muted">
              Corrections you save from writing will appear here.
            </p><article :for={{id, entry} <- @streams.errors} id={id} class="correction-row">
              <div class="row between">
                <strong>{entry.term}</strong><span class="muted text-xs">{if entry.status == "known",
                  do: "Already known",
                  else: "Still practicing"}</span>
              </div><p class="muted text-sm">{entry.meaning}</p>
            </article>
          </div><.link navigate={~p"/review"} class="text-link text-sm">{@progress.due} cards ready to review →</.link>
        </section>
        <section class="sentence-focus stack" aria-label="Time by skill">
          <div class="row between">
            <p class="eyebrow">Time by skill</p><strong>{div(@progress.seconds, 60)} min total</strong>
          </div><div :for={{kind, seconds} <- @progress.skills} class="stack">
            <div class="row between">
              <span class="capitalize">{kind}</span><span class="mono">{div(seconds || 0, 60)} min</span>
            </div><StudyComponents.progress
              value={seconds || 0}
              max={max(@progress.seconds, 1)}
              label={"Time spent on #{kind}"}
            />
          </div><p :if={@progress.skills == []}>
            Complete your first reading or practice activity to start tracking time.
          </p><p class="text-sm">
            {@progress.attempts} saved activities. A little English, every day.
          </p><.link navigate={~p"/practice"} class="text-link">Practice a sentence →</.link>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
