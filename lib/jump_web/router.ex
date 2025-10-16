defmodule JumpWeb.Router do
  use JumpWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JumpWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug JumpWeb.Plugs.AssignCurrentUser
  end

  pipeline :auth do
    plug Ueberauth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_auth do
    plug JumpWeb.Plugs.RequireAuthenticatedUser
  end

  scope "/", JumpWeb do
    pipe_through :browser

    get "/", PageController, :home

    delete "/logout", AuthController, :delete
  end

  scope "/auth", JumpWeb do
    pipe_through [:browser, :auth]

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  scope "/", JumpWeb do
    pipe_through [:browser, :require_auth]

    live "/app", DashboardLive, :index
    live "/chat", ChatLive, :index
  end

  # Webhooks (no authentication, but with signature validation)
  scope "/webhooks", JumpWeb do
    pipe_through [:api]

    post "/hubspot", HubspotWebhookController, :create
    post "/calendar/google", CalendarWebhookController, :create
  end

  # Other scopes may use custom stacks.
  # scope "/api", JumpWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:jump, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: JumpWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
