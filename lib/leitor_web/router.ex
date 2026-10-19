defmodule LeitorWeb.Router do
  use LeitorWeb, :router

  import LeitorWeb.UserAuth

  pipeline :browser_session do
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LeitorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug LeitorWeb.SharingSession
    plug :fetch_current_scope_for_user
    plug LeitorWeb.Locale
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :browser_session
  end

  pipeline :artifact do
    plug :accepts, ["json"]
    plug :browser_session
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Fly readiness checks do not use browser sessions or authentication.
  scope "/", LeitorWeb do
    pipe_through :api
    get "/health", HealthController, :show
  end

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

  scope "/", LeitorWeb do
    pipe_through [:artifact, :require_authenticated_user]
    get "/figures/:id", FigureController, :show
  end

  scope "/", LeitorWeb do
    pipe_through :artifact
    get "/s/:token/figures/:id", SharedFigureController, :show
  end

  ## Authentication routes

  scope "/", LeitorWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/vocabulary", NotebookRedirectController, :words

    live_session :require_authenticated_user,
      on_mount: [{LeitorWeb.UserAuth, :require_authenticated}, {LeitorWeb.Locale, :default}] do
      live "/", LibraryLive, :index
      live "/pages", LibraryLive, :index
      live "/pages/new", PageLive, :new
      live "/pages/:id", PageLive, :show
      live "/notebook", NotebookLive, :index
      live "/settings", PreferencesLive, :index
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end
  end

  scope "/", LeitorWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{LeitorWeb.UserAuth, :mount_current_scope}, {LeitorWeb.Locale, :default}] do
      live "/s/:token", SharedPageLive, :show
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    get "/s/:token/sign-in", SharedFigureController, :sign_in
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
