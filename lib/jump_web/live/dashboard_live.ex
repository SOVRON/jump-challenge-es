defmodule JumpWeb.DashboardLive do
  use JumpWeb, :live_view

  alias Jump.Accounts

  def mount(_params, %{"user_id" => user_id}, socket) do
    # Get current user from session (more efficient than passing full user object)
    current_user = Accounts.get_user!(user_id)

    # Load OAuth accounts for the current user
    oauth_accounts = Accounts.list_oauth_accounts(user_id)

    # Check provider connections
    google_connected = Enum.any?(oauth_accounts, &(&1.provider == :google))
    hubspot_connected = Enum.any?(oauth_accounts, &(&1.provider == :hubspot))

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:google_connected, google_connected)
      |> assign(:hubspot_connected, hubspot_connected)

    {:ok, socket}
  end

  def mount(_params, _session, socket) do
    # Redirect to home if not authenticated
    {:ok, push_navigate(socket, to: ~p"/")}
  end
end
