defmodule LeitorWeb.Router do
  use LeitorWeb, :router

  import LeitorWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LeitorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LeitorWeb do
    pipe_through :browser
  end

  # Other scopes may use custom stacks.
  # scope "/api", LeitorWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:leitor, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LeitorWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", LeitorWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{LeitorWeb.UserAuth, :require_authenticated}] do
      live "/read/:id", ReaderLive, :saved
      live "/library", LibraryLive, :index
      live "/lessons", LessonsLive, :index
      live "/lessons/:id", LessonsLive, :show
      live "/vocabulary", VocabularyLive, :index
      live "/review", ReviewLive, :index
      live "/write", WritingLive, :index
      live "/practice", PracticeLive, :index
      live "/progress", ProgressLive, :index
      live "/rooms", StudyLobbyLive, :index
      live "/rooms/:code", StudyRoomLive, :show
      live "/manage/rooms", RoomLive.Index, :index
      live "/manage/rooms/new", RoomLive.Form, :new
      live "/manage/rooms/:id", RoomLive.Show, :show
      live "/manage/rooms/:id/edit", RoomLive.Form, :edit
      live "/texts", TextLive.Index, :index
      live "/texts/new", TextLive.Form, :new
      live "/texts/:id", TextLive.Show, :show
      live "/texts/:id/edit", TextLive.Form, :edit
      live "/entries", EntryLive.Index, :index
      live "/entries/new", EntryLive.Form, :new
      live "/entries/:id", EntryLive.Show, :show
      live "/entries/:id/edit", EntryLive.Form, :edit
      live "/attempts", AttemptLive.Index, :index
      live "/attempts/new", AttemptLive.Form, :new
      live "/attempts/:id", AttemptLive.Show, :show
      live "/attempts/:id/edit", AttemptLive.Form, :edit
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end
  end

  scope "/", LeitorWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{LeitorWeb.UserAuth, :mount_current_scope}] do
      live "/", ReaderLive, :home
      live "/read", ReaderLive, :sample

      if Application.compile_env(:leitor, :dev_routes) do
        live "/dev/componentes", ComponentGalleryLive, :index
      end

      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
